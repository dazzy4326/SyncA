//
//  FloorMap3DView.swift
//  tohata_ios_02
//
//  3Dリアルタイムヒートマップ
//
//  座標系:
//    物理(mm): X=右方向増加, Y=負値ほど画像上側
//    SceneKit:  X = physX * S,  Y = 高さ,  Z = physY * S
//    テクスチャ: contentsTransform不要 — SCNPlaneをX軸-90度回転した状態で
//              UIImageのデフォルトUVが正しくマッピングされる

import SwiftUI
import SceneKit

struct FloorMap3DView: UIViewRepresentable {
    let appConfig: AppConfig?
    let sensorData: [SensorReading]
    let persons: [PersonPosition]
    let sensor: SensorType
    let floorplanURL: URL?
    var isTopDown: Bool = false
    var highlightTarget: HighlightTarget? = nil
    var recommendation: RecommendationResponse? = nil

    private static let S: Float = 0.001

    // MARK: - Coordinator
    class Coordinator {
        var scnView: SCNView?
        var floorImage: UIImage?
        var imageLoaded = false
        var imageURL: URL?       // 最後に読込を試みたURL
        var prevStamp = ""
        var prevSensorStamp = ""   // センサーデータ変更検知用
        var prevPersonStamp = ""   // 人データ変更検知用
        var currentIsTopDown: Bool?  // カメラ状態追跡
        var profileImages: [String: UIImage] = [:]  // beacon_id → プロフィール画像キャッシュ
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - makeUIView
    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = UIColor(white: 0.12, alpha: 1)
        v.allowsCameraControl = true
        v.autoenablesDefaultLighting = true
        v.antialiasingMode = .multisampling2X  // 実機GPU負荷軽減（4X→2X）
        v.preferredFramesPerSecond = 30         // 実機バッテリー消費軽減

        let scene = SCNScene()
        v.scene = scene

        // 環境光
        let amb = SCNNode()
        amb.light = SCNLight()
        amb.light!.type = .ambient
        amb.light!.intensity = 500
        scene.rootNode.addChildNode(amb)

        // 指向性ライト（シャドウ無効で描画負荷軽減）
        let dir = SCNNode()
        dir.light = SCNLight()
        dir.light!.type = .directional
        dir.light!.intensity = 600
        dir.light!.castsShadow = false
        dir.position = SCNVector3(4, 10, 2)
        dir.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 6, 0)
        scene.rootNode.addChildNode(dir)

        // カメラ
        let cam = SCNNode()
        cam.name = "cam"
        cam.camera = SCNCamera()
        cam.camera!.zNear = 0.01
        cam.camera!.zFar = 200
        scene.rootNode.addChildNode(cam)

        context.coordinator.scnView = v
        return v
    }

    // MARK: - updateUIView
    func updateUIView(_ v: SCNView, context: Context) {
        let coord = context.coordinator
        guard let scene = v.scene else { return }

        // 画像がまだ読み込まれていなければ読込開始
        if !coord.imageLoaded, let url = floorplanURL, url != coord.imageURL {
            coord.imageURL = url
            loadFloorImage(coord: coord)
        }

        // config変更 → 静的シーン再構築（壁・机・柱など）
        let objStamp = (appConfig?.FLOOR_OBJECTS ?? []).map {
            "\($0.type),\($0.x1),\($0.y1),\($0.x2),\($0.y2),\($0.height ?? 0),\($0.color ?? ""),\($0.count ?? 0),\($0.rotation ?? 0)"
        }.joined(separator: ";")
        let stamp = "\(appConfig?.FLOOR_BOUNDARY?.count ?? 0)|\(objStamp)|\(appConfig?.PI_LOCATIONS?.count ?? 0)"
        var configChanged = false
        if stamp != coord.prevStamp {
            coord.prevStamp = stamp
            configChanged = true
            scene.rootNode.childNode(withName: "floor", recursively: false)?.removeFromParentNode()
            rebuildStatic(scene: scene)
        }

        // カメラ切替（2D俯瞰 ↔ 3D視点）
        if coord.currentIsTopDown != isTopDown {
            coord.currentIsTopDown = isTopDown
            if let camNode = scene.rootNode.childNode(withName: "cam", recursively: false) {
                applyCameraMode(camNode: camNode, scnView: v)
            }
        }

        // センサーデータ変更 or config変更 or 画像読込完了時にテクスチャ再描画
        let sensorStamp = sensorData.map { "\($0.id):\($0.value(for: sensor) ?? 0)" }.joined(separator: ",")
            + "|\(sensor.rawValue)|\(coord.imageLoaded)"
        let sensorChanged = sensorStamp != coord.prevSensorStamp
        if sensorChanged || configChanged {
            coord.prevSensorStamp = sensorStamp
            updateBeaconLabels(scene: scene)
            updateFloorTexture(scene: scene, coord: coord)
        }

        // 人データ変更時のみ人マーカー再描画
        let personStamp = persons.map { "\($0.id):\($0.estimated_x ?? 0):\($0.estimated_y ?? 0):\($0.status ?? "")" }.joined(separator: ",")
            + "|\(highlightTarget?.beaconId ?? "")"
        if personStamp != coord.prevPersonStamp {
            coord.prevPersonStamp = personStamp
            updatePersons(scene: scene, coord: coord)
        }

        updateRecommendationZone(scene: scene)
    }

    // MARK: - カメラモード適用
    private func applyCameraMode(camNode: SCNNode, scnView: SCNView) {
        guard let camera = camNode.camera else { return }

        // 部屋中心を計算（FLOOR_BOUNDARY or デフォルト）
        let cx: Float = 3.94, cz: Float = -3.37  // 部屋の概算中心

        if isTopDown {
            // 2D俯瞰モード: 真上から正射影
            camera.usesOrthographicProjection = true
            camera.orthographicScale = 6.0  // 部屋全体が収まるスケール
            camera.fieldOfView = 50
            camNode.position = SCNVector3(cx, 30, cz)
            camNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
            scnView.allowsCameraControl = false
            scnView.pointOfView = camNode
        } else {
            // 3D視点モード: 透視投影
            camera.usesOrthographicProjection = false
            camera.fieldOfView = 50
            camNode.position = SCNVector3(4, 12, 4)
            camNode.look(at: SCNVector3(4, 0, -5))
            scnView.allowsCameraControl = true
            scnView.pointOfView = camNode
        }
    }

    // MARK: - 画像読み込み
    private func loadFloorImage(coord: Coordinator) {
        guard let url = coord.imageURL else { return }
        print("[3D] 画像読込開始: \(url)")
        Task {
            do {
                let (data, _) = try await ServerConfig.session.data(from: url)
                if let img = UIImage(data: data) {
                    print("[3D] 画像読込成功: \(img.size)")
                    await MainActor.run {
                        coord.floorImage = img
                        coord.imageLoaded = true
                        if let scene = coord.scnView?.scene {
                            updateFloorTexture(scene: scene, coord: coord)
                        }
                    }
                }
            } catch {
                print("[3D] 画像読込失敗: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 静的シーン（壁・机・柱・ビーコンピン）
    private func rebuildStatic(scene: SCNScene) {
        scene.rootNode.childNodes
            .filter { $0.name?.hasPrefix("s_") == true }
            .forEach { $0.removeFromParentNode() }

        let s = Self.S

        // --- 窓オブジェクトを事前収集（壁くり抜き用） ---
        let allWindows: [FloorObject] = (appConfig?.FLOOR_OBJECTS ?? []).filter { $0.type == "window" }

        // --- FLOOR_BOUNDARY 壁（白、厚み有り） ---
        if let bd = appConfig?.FLOOR_BOUNDARY, bd.count >= 3 {
            let wallH: Float = 2800 * s  // 2800mm
            let wallColor = UIColor.white.withAlphaComponent(0.9)
            for i in 0..<bd.count {
                let a = bd[i], b = bd[(i + 1) % bd.count]
                let wins = windowsOnSegment(
                    wx1: Float(a.x), wy1: Float(a.y),
                    wx2: Float(b.x), wy2: Float(b.y),
                    windows: allWindows
                )
                if wins.isEmpty {
                    let n = makeWall(
                        x1: Float(a.x), y1: Float(a.y),
                        x2: Float(b.x), y2: Float(b.y),
                        height: wallH, thickness: 0.12, color: wallColor
                    )
                    n.name = "s_bw\(i)"
                    scene.rootNode.addChildNode(n)
                } else {
                    let n = makeWallWithWindows(
                        wx1: Float(a.x), wy1: Float(a.y),
                        wx2: Float(b.x), wy2: Float(b.y),
                        wallHeight: wallH, wallColor: wallColor,
                        wallThickness: 0.12, windows: wins
                    )
                    n.name = "s_bw\(i)"
                    scene.rootNode.addChildNode(n)
                }
            }
        }

        // --- FLOOR_OBJECTS ---
        if let objs = appConfig?.FLOOR_OBJECTS {
            for (i, obj) in objs.enumerated() {
                let customColor = obj.color.flatMap { Self.uiColorFromHex($0) }
                print("[3D] オブジェクト[\(i)] type=\(obj.type), color=\(obj.color ?? "nil") → UIColor=\(customColor?.description ?? "default")")
                let n: SCNNode
                switch obj.type {
                case "wall":
                    let h = Float(obj.height ?? 2800) * s
                    let wc = customColor ?? UIColor.white.withAlphaComponent(0.9)
                    let wins = windowsOnSegment(
                        wx1: Float(obj.x1), wy1: Float(obj.y1),
                        wx2: Float(obj.x2), wy2: Float(obj.y2),
                        windows: allWindows
                    )
                    if wins.isEmpty {
                        n = makeWall(
                            x1: Float(obj.x1), y1: Float(obj.y1),
                            x2: Float(obj.x2), y2: Float(obj.y2),
                            height: h, thickness: 0.12, color: wc
                        )
                    } else {
                        n = makeWallWithWindows(
                            wx1: Float(obj.x1), wy1: Float(obj.y1),
                            wx2: Float(obj.x2), wy2: Float(obj.y2),
                            wallHeight: h, wallColor: wc,
                            wallThickness: 0.12, windows: wins
                        )
                    }
                case "pillar":
                    let h = Float(obj.height ?? 2800) * s
                    n = makeBox(
                        x1: Float(obj.x1), y1: Float(obj.y1),
                        x2: Float(obj.x2), y2: Float(obj.y2),
                        height: h,
                        color: customColor ?? UIColor.black.withAlphaComponent(0.85)
                    )
                case "shelf":
                    let h = Float(obj.height ?? 1500) * s
                    n = makeShelf(
                        x1: Float(obj.x1), y1: Float(obj.y1),
                        x2: Float(obj.x2), y2: Float(obj.y2),
                        height: h,
                        color: customColor
                    )
                case "plant":
                    let h = Float(obj.height ?? 1200) * s
                    n = makePlant(
                        x1: Float(obj.x1), y1: Float(obj.y1),
                        x2: Float(obj.x2), y2: Float(obj.y2),
                        height: h,
                        potColor: customColor
                    )
                case "monitor":
                    let h = Float(obj.height ?? 720) * s
                    let rotDeg = Float(obj.rotation ?? 0)
                    let rotRad = rotDeg * .pi / 180
                    let mcx = (Float(obj.x1) + Float(obj.x2)) / 2 * s
                    let mcz = (Float(obj.y1) + Float(obj.y2)) / 2 * s
                    n = makeMonitor(
                        cx: mcx, cz: mcz,
                        height: h,
                        rotation: rotRad,
                        color: customColor
                    )
                case "chair":
                    let h = Float(obj.height ?? 450) * s
                    let cnt = max(1, obj.count ?? 1)
                    let rotDeg = Float(obj.rotation ?? 0)
                    let rotRad = rotDeg * .pi / 180  // 度→ラジアン
                    // 直線上に均等配置
                    let container = SCNNode()
                    for ci in 0..<cnt {
                        let t: Float = cnt == 1 ? 0.5 : Float(ci) / Float(cnt - 1)
                        let px = Float(obj.x1) + (Float(obj.x2) - Float(obj.x1)) * t
                        let py = Float(obj.y1) + (Float(obj.y2) - Float(obj.y1)) * t
                        let chair = makeChair(
                            cx: px * s, cz: py * s,
                            height: h,
                            rotation: rotRad,
                            seatColor: customColor
                        )
                        container.addChildNode(chair)
                    }
                    n = container
                case "window":
                    n = SCNNode()  // 窓は壁描画時にくり抜き＋埋め込みで処理
                default: // desk
                    let h = Float(obj.height ?? 700) * s
                    n = makeDesk(
                        x1: Float(obj.x1), y1: Float(obj.y1),
                        x2: Float(obj.x2), y2: Float(obj.y2),
                        height: h,
                        color: customColor
                    )
                }
                n.name = "s_fo\(i)"
                scene.rootNode.addChildNode(n)
            }
        }

        // --- ビーコンピン（ピンのみ。ラベルはupdateBeaconLabelsで動的更新） ---
        let piLocs = piPositions()
        print("[3D] ビーコン数: \(piLocs.count), センサーデータ数: \(sensorData.count)")
        for (i, pi) in piLocs.enumerated() {
            let pinH: Float = 500 * s  // 500mm
            let cyl = SCNCylinder(radius: 0.03, height: CGFloat(pinH))
            cyl.firstMaterial?.diffuse.contents = UIColor.red
            let pinNode = SCNNode(geometry: cyl)
            pinNode.name = "s_bp\(i)"
            pinNode.position = SCNVector3(Float(pi.x) * s, pinH / 2, Float(pi.y) * s)
            scene.rootNode.addChildNode(pinNode)

            // 先端球
            let tip = SCNSphere(radius: 0.06)
            tip.firstMaterial?.diffuse.contents = UIColor.red
            let tipN = SCNNode(geometry: tip)
            tipN.position = SCNVector3(0, pinH / 2 + 0.06, 0)
            pinNode.addChildNode(tipN)
        }
    }

    // MARK: - ビーコンラベル動的更新（センサー値が毎回変わるため）
    private func updateBeaconLabels(scene: SCNScene) {
        // 既存ラベルを削除
        scene.rootNode.childNodes
            .filter { $0.name?.hasPrefix("bl_") == true }
            .forEach { $0.removeFromParentNode() }

        let s = Self.S
        let piLocs = piPositions()
        let rMap = Dictionary(sensorData.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        for (i, pi) in piLocs.enumerated() {
            let pinH: Float = 500 * s
            let valText: String
            if let r = rMap[pi.id] {
                valText = String(format: "%.1f%@", r.value(for: sensor), sensor.unit)
            } else { valText = "---" }
            let lb = billboardLabel("\(pi.id)\n\(valText)", size: 36, bg: .black, scale: 0.008)
            lb.name = "bl_\(i)"
            lb.position = SCNVector3(Float(pi.x) * s, pinH + 0.4, Float(pi.y) * s)
            scene.rootNode.addChildNode(lb)
        }
    }

    // MARK: - 壁ノード
    private func makeWall(x1: Float, y1: Float, x2: Float, y2: Float, height: Float, thickness: Float = 0.12, color: UIColor) -> SCNNode {
        let s = Self.S
        let ax = x1 * s, az = y1 * s
        let bx = x2 * s, bz = y2 * s
        let dx = bx - ax, dz = bz - az
        let len = sqrt(dx * dx + dz * dz)
        let ang = atan2(dz, dx)

        let box = SCNBox(width: CGFloat(len), height: CGFloat(height), length: CGFloat(thickness), chamferRadius: 0)
        box.firstMaterial?.diffuse.contents = color
        let n = SCNNode(geometry: box)
        n.position = SCNVector3((ax + bx) / 2, height / 2, (az + bz) / 2)
        n.eulerAngles.y = -ang
        return n
    }

    // MARK: - 壁線上の窓を検出（座標はmm単位）
    private struct SegmentWindow {
        let tStart: Float   // 壁線上のパラメータ 0〜1
        let tEnd: Float
        let heightStart: Float  // シーン単位
        let heightEnd: Float
        let color: UIColor?
    }

    private func windowsOnSegment(wx1: Float, wy1: Float, wx2: Float, wy2: Float,
                                  windows: [FloorObject]) -> [SegmentWindow] {
        let s = Self.S
        let wdx = wx2 - wx1, wdy = wy2 - wy1
        let wallLen2 = wdx * wdx + wdy * wdy
        guard wallLen2 > 1 else { return [] }
        let wallLen = sqrt(wallLen2)
        let tolerance: Float = 200  // 200mm許容

        var result: [SegmentWindow] = []
        for win in windows {
            let p1x = Float(win.x1), p1y = Float(win.y1)
            let p2x = Float(win.x2), p2y = Float(win.y2)
            // 壁線からの距離チェック
            let dist1 = abs((p1x - wx1) * wdy - (p1y - wy1) * wdx) / wallLen
            let dist2 = abs((p2x - wx1) * wdy - (p2y - wy1) * wdx) / wallLen
            guard dist1 < tolerance && dist2 < tolerance else { continue }
            // 壁線上のパラメータ
            let t1 = ((p1x - wx1) * wdx + (p1y - wy1) * wdy) / wallLen2
            let t2 = ((p2x - wx1) * wdx + (p2y - wy1) * wdy) / wallLen2
            let tMin = max(0, min(t1, t2))
            let tMax = min(1, max(t1, t2))
            guard tMax > 0 && tMin < 1 else { continue }
            result.append(SegmentWindow(
                tStart: tMin, tEnd: tMax,
                heightStart: Float(win.height_start ?? 0) * s,
                heightEnd: Float(win.height ?? 2000) * s,
                color: win.color.flatMap { Self.uiColorFromHex($0) }
            ))
        }
        return result.sorted { $0.tStart < $1.tStart }
    }

    // MARK: - 壁を窓でくり抜いて描画
    private func makeWallWithWindows(wx1: Float, wy1: Float, wx2: Float, wy2: Float,
                                     wallHeight: Float, wallColor: UIColor, wallThickness: Float,
                                     windows: [SegmentWindow]) -> SCNNode {
        let container = SCNNode()
        var currentT: Float = 0

        for win in windows {
            // 窓手前の壁セグメント
            if win.tStart > currentT + 0.001 {
                let sx = wx1 + (wx2 - wx1) * currentT
                let sy = wy1 + (wy2 - wy1) * currentT
                let ex = wx1 + (wx2 - wx1) * win.tStart
                let ey = wy1 + (wy2 - wy1) * win.tStart
                let wallNode = makeWall(x1: sx, y1: sy, x2: ex, y2: ey,
                                        height: wallHeight, thickness: wallThickness, color: wallColor)
                container.addChildNode(wallNode)
            }
            // 窓セクション（上下壁 + ガラス + 枠）
            let winX1 = wx1 + (wx2 - wx1) * win.tStart
            let winY1 = wy1 + (wy2 - wy1) * win.tStart
            let winX2 = wx1 + (wx2 - wx1) * win.tEnd
            let winY2 = wy1 + (wy2 - wy1) * win.tEnd
            let windowNode = makeWindowEmbedded(
                x1: winX1, y1: winY1, x2: winX2, y2: winY2,
                heightStart: win.heightStart, heightEnd: win.heightEnd,
                wallHeight: wallHeight, wallThickness: wallThickness,
                wallColor: wallColor, glassColor: win.color
            )
            container.addChildNode(windowNode)
            currentT = win.tEnd
        }

        // 最後の壁セグメント
        if currentT < 1 - 0.001 {
            let sx = wx1 + (wx2 - wx1) * currentT
            let sy = wy1 + (wy2 - wy1) * currentT
            let wallNode = makeWall(x1: sx, y1: sy, x2: wx2, y2: wy2,
                                    height: wallHeight, thickness: wallThickness, color: wallColor)
            container.addChildNode(wallNode)
        }
        return container
    }

    // MARK: - 壁埋め込み窓ノード（上下壁 + ガラス + 窓枠）
    private func makeWindowEmbedded(x1: Float, y1: Float, x2: Float, y2: Float,
                                    heightStart: Float, heightEnd: Float,
                                    wallHeight: Float, wallThickness: Float,
                                    wallColor: UIColor, glassColor: UIColor? = nil) -> SCNNode {
        let s = Self.S
        let ax = x1 * s, az = y1 * s
        let bx = x2 * s, bz = y2 * s
        let dx = bx - ax, dz = bz - az
        let len = sqrt(dx * dx + dz * dz)
        let ang = atan2(dz, dx)
        let cx = (ax + bx) / 2, cz = (az + bz) / 2
        let glassH = max(heightEnd - heightStart, 0.01)
        let centerY = heightStart + glassH / 2

        let parent = SCNNode()

        // --- 下部の壁（床〜窓下端） ---
        if heightStart > 0.001 {
            let lowerH = heightStart
            let lower = SCNBox(width: CGFloat(len), height: CGFloat(lowerH), length: CGFloat(wallThickness), chamferRadius: 0)
            lower.firstMaterial?.diffuse.contents = wallColor
            let lowerNode = SCNNode(geometry: lower)
            lowerNode.position = SCNVector3(cx, lowerH / 2, cz)
            lowerNode.eulerAngles.y = -ang
            parent.addChildNode(lowerNode)
        }

        // --- 上部の壁（窓上端〜天井） ---
        if heightEnd < wallHeight - 0.001 {
            let upperH = wallHeight - heightEnd
            let upper = SCNBox(width: CGFloat(len), height: CGFloat(upperH), length: CGFloat(wallThickness), chamferRadius: 0)
            upper.firstMaterial?.diffuse.contents = wallColor
            let upperNode = SCNNode(geometry: upper)
            upperNode.position = SCNVector3(cx, heightEnd + upperH / 2, cz)
            upperNode.eulerAngles.y = -ang
            parent.addChildNode(upperNode)
        }

        // --- ガラスパネル（半透明） ---
        let gc = glassColor ?? UIColor(red: 0.7, green: 0.85, blue: 1.0, alpha: 1.0)
        let glass = SCNBox(width: CGFloat(len), height: CGFloat(glassH), length: CGFloat(wallThickness * 0.15), chamferRadius: 0)
        let glassMat = SCNMaterial()
        glassMat.diffuse.contents = gc.withAlphaComponent(0.2)
        glassMat.transparent.contents = UIColor.white.withAlphaComponent(0.25)
        glassMat.emission.contents = UIColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 0.1)
        glassMat.isDoubleSided = true
        glassMat.transparencyMode = .dualLayer
        glass.materials = [glassMat]
        let glassNode = SCNNode(geometry: glass)
        glassNode.position = SCNVector3(cx, centerY, cz)
        glassNode.eulerAngles.y = -ang
        parent.addChildNode(glassNode)

        // --- 窓枠（上下左右） ---
        let frameColor = UIColor(white: 0.7, alpha: 1.0)
        let frameW: Float = 0.025

        // 上枠
        let topBar = SCNBox(width: CGFloat(len), height: CGFloat(frameW), length: CGFloat(wallThickness + 0.01), chamferRadius: 0)
        topBar.firstMaterial?.diffuse.contents = frameColor
        let topNode = SCNNode(geometry: topBar)
        topNode.position = SCNVector3(cx, heightEnd, cz)
        topNode.eulerAngles.y = -ang
        parent.addChildNode(topNode)

        // 下枠
        let botBar = SCNBox(width: CGFloat(len), height: CGFloat(frameW), length: CGFloat(wallThickness + 0.01), chamferRadius: 0)
        botBar.firstMaterial?.diffuse.contents = frameColor
        let botNode = SCNNode(geometry: botBar)
        botNode.position = SCNVector3(cx, heightStart, cz)
        botNode.eulerAngles.y = -ang
        parent.addChildNode(botNode)

        // 左枠
        let leftBar = SCNBox(width: CGFloat(frameW), height: CGFloat(glassH + frameW * 2), length: CGFloat(wallThickness + 0.01), chamferRadius: 0)
        leftBar.firstMaterial?.diffuse.contents = frameColor
        let leftNode = SCNNode(geometry: leftBar)
        leftNode.position = SCNVector3(ax, centerY, az)
        leftNode.eulerAngles.y = -ang
        parent.addChildNode(leftNode)

        // 右枠
        let rightBar = SCNBox(width: CGFloat(frameW), height: CGFloat(glassH + frameW * 2), length: CGFloat(wallThickness + 0.01), chamferRadius: 0)
        rightBar.firstMaterial?.diffuse.contents = frameColor
        let rightNode = SCNNode(geometry: rightBar)
        rightNode.position = SCNVector3(bx, centerY, bz)
        rightNode.eulerAngles.y = -ang
        parent.addChildNode(rightNode)

        return parent
    }

    // MARK: - ボックスノード（柱）
    private func makeBox(x1: Float, y1: Float, x2: Float, y2: Float, height: Float, color: UIColor) -> SCNNode {
        let s = Self.S
        let ax = min(x1, x2) * s, bx = max(x1, x2) * s
        let az = min(y1, y2) * s, bz = max(y1, y2) * s
        let w = bx - ax, d = bz - az

        let box = SCNBox(width: CGFloat(max(w, 0.01)), height: CGFloat(height), length: CGFloat(max(d, 0.01)), chamferRadius: 0.005)
        box.firstMaterial?.diffuse.contents = color
        let n = SCNNode(geometry: box)
        n.position = SCNVector3((ax + bx) / 2, height / 2, (az + bz) / 2)
        return n
    }

    // MARK: - 机ノード（天板 + 4本脚）
    private func makeDesk(x1: Float, y1: Float, x2: Float, y2: Float, height: Float, color: UIColor? = nil) -> SCNNode {
        let s = Self.S
        let ax = min(x1, x2) * s, bx = max(x1, x2) * s
        let az = min(y1, y2) * s, bz = max(y1, y2) * s
        let w = max(bx - ax, 0.01)
        let d = max(bz - az, 0.01)
        let topThick: Float = 0.03
        let legR: Float = 0.015
        let legH = max(height - topThick, 0.01)
        let cx = (ax + bx) / 2, cz = (az + bz) / 2

        let parent = SCNNode()
        let topColor = color ?? UIColor(red: 0.55, green: 0.35, blue: 0.15, alpha: 0.9)

        // 天板
        let top = SCNBox(width: CGFloat(w), height: CGFloat(topThick), length: CGFloat(d), chamferRadius: 0.005)
        top.firstMaterial?.diffuse.contents = topColor
        let topN = SCNNode(geometry: top)
        topN.position = SCNVector3(cx, height - topThick / 2, cz)
        parent.addChildNode(topN)

        // 4本脚
        let leg = SCNCylinder(radius: CGFloat(legR), height: CGFloat(legH))
        leg.firstMaterial?.diffuse.contents = UIColor(white: 0.3, alpha: 1)
        let inX = min(w * 0.1, 0.05)
        let inZ = min(d * 0.1, 0.05)
        let positions = [
            SCNVector3(ax + inX, legH / 2, az + inZ),
            SCNVector3(bx - inX, legH / 2, az + inZ),
            SCNVector3(ax + inX, legH / 2, bz - inZ),
            SCNVector3(bx - inX, legH / 2, bz - inZ)
        ]
        for pos in positions {
            let legN = SCNNode(geometry: leg)
            legN.position = pos
            parent.addChildNode(legN)
        }

        return parent
    }

    // MARK: - 棚ノード
    private func makeShelf(x1: Float, y1: Float, x2: Float, y2: Float, height: Float, color: UIColor? = nil) -> SCNNode {
        let s = Self.S
        let ax = min(x1, x2) * s, bx = max(x1, x2) * s
        let az = min(y1, y2) * s, bz = max(y1, y2) * s
        let w = max(bx - ax, 0.01)
        let d = max(bz - az, 0.01)
        let cx = (ax + bx) / 2, cz = (az + bz) / 2
        let boardThick: Float = 0.015
        let poleR: Float = 0.012

        let parent = SCNNode()
        let frameColor = color ?? UIColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1)
        let boardColor = color?.withAlphaComponent(0.8) ?? UIColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 0.9)

        // 4本の支柱（角に配置）
        let pole = SCNCylinder(radius: CGFloat(poleR), height: CGFloat(height))
        pole.firstMaterial?.diffuse.contents = frameColor
        let polePositions = [
            SCNVector3(ax + poleR, height / 2, az + poleR),
            SCNVector3(bx - poleR, height / 2, az + poleR),
            SCNVector3(ax + poleR, height / 2, bz - poleR),
            SCNVector3(bx - poleR, height / 2, bz - poleR)
        ]
        for pos in polePositions {
            let pn = SCNNode(geometry: pole)
            pn.position = pos
            parent.addChildNode(pn)
        }

        // 棚板（等間隔、底板含む4段）
        let shelfCount = max(3, Int(height / 0.12))
        for i in 0...shelfCount {
            let y = Float(i) / Float(shelfCount) * height
            let board = SCNBox(width: CGFloat(w), height: CGFloat(boardThick), length: CGFloat(d), chamferRadius: 0.002)
            board.firstMaterial?.diffuse.contents = boardColor
            let bn = SCNNode(geometry: board)
            bn.position = SCNVector3(cx, y, cz)
            parent.addChildNode(bn)
        }

        return parent
    }

    // MARK: - 観葉植物ノード（鉢 + 幹 + 葉球体群）固定サイズ
    private func makePlant(x1: Float, y1: Float, x2: Float, y2: Float, height: Float, potColor: UIColor? = nil) -> SCNNode {
        let s = Self.S
        let cx = (min(x1, x2) + max(x1, x2)) / 2 * s
        let cz = (min(y1, y2) + max(y1, y2)) / 2 * s
        // 固定サイズの鉢
        let potRadius: Float = 0.12

        let parent = SCNNode()

        // 鉢（円筒）
        let potH: Float = height * 0.25
        let pot = SCNCylinder(radius: CGFloat(potRadius), height: CGFloat(potH))
        pot.firstMaterial?.diffuse.contents = potColor ?? UIColor(red: 0.65, green: 0.35, blue: 0.2, alpha: 1)
        let potNode = SCNNode(geometry: pot)
        potNode.position = SCNVector3(cx, potH / 2, cz)
        parent.addChildNode(potNode)

        // 土（ダークブラウン円盤）
        let soil = SCNCylinder(radius: CGFloat(potRadius * 0.9), height: 0.01)
        soil.firstMaterial?.diffuse.contents = UIColor(red: 0.25, green: 0.15, blue: 0.08, alpha: 1)
        let soilNode = SCNNode(geometry: soil)
        soilNode.position = SCNVector3(cx, potH, cz)
        parent.addChildNode(soilNode)

        // 幹
        let trunkH = height * 0.45
        let trunk = SCNCylinder(radius: CGFloat(potRadius * 0.15), height: CGFloat(trunkH))
        trunk.firstMaterial?.diffuse.contents = UIColor(red: 0.4, green: 0.25, blue: 0.1, alpha: 1)
        let trunkNode = SCNNode(geometry: trunk)
        trunkNode.position = SCNVector3(cx, potH + trunkH / 2, cz)
        parent.addChildNode(trunkNode)

        // 葉（複数の球体でこんもりした形）
        let leafBase = potH + trunkH
        let leafR = max(potRadius * 1.5, 0.1)
        let leafPositions: [(Float, Float, Float, Float)] = [
            (0, leafR * 0.6, 0, leafR),
            (-leafR * 0.4, leafR * 0.3, leafR * 0.3, leafR * 0.7),
            (leafR * 0.4, leafR * 0.3, -leafR * 0.3, leafR * 0.7),
            (0, leafR * 0.2, -leafR * 0.4, leafR * 0.6),
            (leafR * 0.3, leafR * 0.5, leafR * 0.2, leafR * 0.65),
        ]
        for (dx, dy, dz, r) in leafPositions {
            let leaf = SCNSphere(radius: CGFloat(r))
            leaf.firstMaterial?.diffuse.contents = UIColor(red: 0.15, green: 0.55, blue: 0.15, alpha: 0.85)
            let ln = SCNNode(geometry: leaf)
            ln.position = SCNVector3(cx + dx, leafBase + dy, cz + dz)
            parent.addChildNode(ln)
        }

        return parent
    }

    // MARK: - 椅子ノード（座面 + 背もたれ + 中央支柱 + キャスター）固定サイズ・回転対応
    // cx, cz: ワールド座標系での中心位置、rotation: Y軸回りの回転（ラジアン、0=北向き）
    private func makeChair(cx: Float, cz: Float, height: Float, rotation: Float = 0, seatColor: UIColor? = nil) -> SCNNode {
        // 固定サイズ
        let w: Float = 0.45
        let d: Float = 0.45
        let seatThick: Float = 0.03
        let seatH = height
        let legR: Float = 0.012

        // 原点中心で組み立て → 最後に回転+移動
        let parent = SCNNode()
        let chairColor = seatColor ?? UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 0.9)

        // 座面
        let seat = SCNBox(width: CGFloat(w), height: CGFloat(seatThick), length: CGFloat(d), chamferRadius: 0.005)
        seat.firstMaterial?.diffuse.contents = chairColor
        let seatN = SCNNode(geometry: seat)
        seatN.position = SCNVector3(0, seatH, 0)
        parent.addChildNode(seatN)

        // 背もたれ（-Z方向=北側）
        let backH: Float = seatH * 0.7
        let backThick: Float = 0.02
        let back = SCNBox(width: CGFloat(w * 0.9), height: CGFloat(backH), length: CGFloat(backThick), chamferRadius: 0.005)
        back.firstMaterial?.diffuse.contents = chairColor
        let backN = SCNNode(geometry: back)
        backN.position = SCNVector3(0, seatH + backH / 2, -d / 2 + backThick / 2)
        parent.addChildNode(backN)

        // 中央支柱
        let poleH = seatH - 0.02
        let pole = SCNCylinder(radius: CGFloat(legR * 1.5), height: CGFloat(poleH))
        pole.firstMaterial?.diffuse.contents = UIColor(white: 0.35, alpha: 1)
        let poleN = SCNNode(geometry: pole)
        poleN.position = SCNVector3(0, poleH / 2, 0)
        parent.addChildNode(poleN)

        // キャスター脚（星型5本）
        let legLen = max(w, d) * 0.5
        for i in 0..<5 {
            let angle = Float(i) * (2 * .pi / 5)
            let lx = cos(angle) * legLen
            let lz = sin(angle) * legLen

            let leg = SCNCylinder(radius: CGFloat(legR), height: CGFloat(legLen))
            leg.firstMaterial?.diffuse.contents = UIColor(white: 0.35, alpha: 1)
            let legN = SCNNode(geometry: leg)
            legN.position = SCNVector3(lx / 2, legR, lz / 2)
            legN.eulerAngles.z = .pi / 2
            legN.eulerAngles.y = -angle
            parent.addChildNode(legN)

            // キャスター球
            let caster = SCNSphere(radius: CGFloat(legR * 1.5))
            caster.firstMaterial?.diffuse.contents = UIColor(white: 0.25, alpha: 1)
            let cn = SCNNode(geometry: caster)
            cn.position = SCNVector3(lx, legR * 1.5, lz)
            parent.addChildNode(cn)
        }

        // 回転（Y軸回り）と移動を適用
        parent.eulerAngles.y = rotation
        parent.position = SCNVector3(cx, 0, cz)

        return parent
    }

    // MARK: - PCモニターノード（画面パネル + スタンド + 台座）
    // cx, cz: ワールド座標系での中心位置、rotation: Y軸回りの回転（ラジアン、0=北向き）
    private func makeMonitor(cx: Float, cz: Float, height: Float, rotation: Float = 0, color: UIColor? = nil) -> SCNNode {
        // 固定サイズ（実寸ベース）
        let screenW: Float = 0.55   // 画面幅 550mm
        let screenH: Float = 0.35   // 画面高さ 350mm
        let screenThick: Float = 0.02
        let bezelColor = color ?? UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)
        let screenColor = UIColor(red: 0.1, green: 0.15, blue: 0.25, alpha: 1)  // 暗い画面

        let parent = SCNNode()

        // 台座（楕円ベース）
        let baseW: Float = 0.25, baseD: Float = 0.15, baseH: Float = 0.015
        let base = SCNBox(width: CGFloat(baseW), height: CGFloat(baseH), length: CGFloat(baseD), chamferRadius: CGFloat(baseH / 2))
        base.firstMaterial?.diffuse.contents = bezelColor
        let baseNode = SCNNode(geometry: base)
        baseNode.position = SCNVector3(0, height + baseH / 2, 0)
        parent.addChildNode(baseNode)

        // スタンド（支柱）
        let standH: Float = 0.12
        let standW: Float = 0.03
        let stand = SCNBox(width: CGFloat(standW), height: CGFloat(standH), length: CGFloat(standW), chamferRadius: 0.003)
        stand.firstMaterial?.diffuse.contents = bezelColor
        let standNode = SCNNode(geometry: stand)
        standNode.position = SCNVector3(0, height + baseH + standH / 2, 0)
        parent.addChildNode(standNode)

        // 画面パネル（ベゼル）
        let panelBottom = height + baseH + standH
        let panel = SCNBox(width: CGFloat(screenW), height: CGFloat(screenH), length: CGFloat(screenThick), chamferRadius: 0.005)
        panel.firstMaterial?.diffuse.contents = bezelColor
        let panelNode = SCNNode(geometry: panel)
        panelNode.position = SCNVector3(0, panelBottom + screenH / 2, 0)
        parent.addChildNode(panelNode)

        // 画面（ベゼル内側、少し前面に）
        let inset: Float = 0.02
        let dispW = screenW - inset * 2
        let dispH = screenH - inset * 2
        let display = SCNBox(width: CGFloat(dispW), height: CGFloat(dispH), length: CGFloat(screenThick + 0.001), chamferRadius: 0)
        display.firstMaterial?.diffuse.contents = screenColor
        display.firstMaterial?.emission.contents = UIColor(red: 0.05, green: 0.08, blue: 0.15, alpha: 1)
        let displayNode = SCNNode(geometry: display)
        displayNode.position = SCNVector3(0, panelBottom + screenH / 2, screenThick / 2 + 0.0005)
        parent.addChildNode(displayNode)

        // 向きと位置を適用（椅子と同じ方式）
        parent.eulerAngles.y = rotation
        parent.position = SCNVector3(cx, 0, cz)

        return parent
    }

    // MARK: - ビルボードラベル
    private func billboardLabel(_ text: String, size: CGFloat, bg: UIColor, scale: CGFloat = 0.006) -> SCNNode {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        let ts = (text as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 6
        let imgSize = CGSize(width: ts.width + pad * 2, height: ts.height + pad)

        let r = UIGraphicsImageRenderer(size: imgSize)
        let img = r.image { _ in
            bg.withAlphaComponent(0.85).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: imgSize), cornerRadius: 4).fill()
            (text as NSString).draw(at: CGPoint(x: pad, y: pad / 2), withAttributes: attrs)
        }

        let plane = SCNPlane(width: imgSize.width * scale, height: imgSize.height * scale)
        plane.firstMaterial?.diffuse.contents = img
        plane.firstMaterial?.lightingModel = .constant
        plane.firstMaterial?.isDoubleSided = true
        let n = SCNNode(geometry: plane)
        n.constraints = [SCNBillboardConstraint()]
        return n
    }

    // MARK: - 床面テクスチャ
    private func updateFloorTexture(scene: SCNScene, coord: Coordinator) {
        let imgW = appConfig?.FLOORPLAN_IMAGE?.width ?? 1483
        let imgH = appConfig?.FLOORPLAN_IMAGE?.height ?? 1753
        let texSize = CGSize(width: Int(imgW), height: Int(imgH))

        let piLocs = piPositions()

        // FLOOR_BOUNDARYクリッピング用のポイントを事前計算
        let boundaryPts: [CGPoint]?
        if let bd = appConfig?.FLOOR_BOUNDARY, bd.count >= 3 {
            boundaryPts = bd.map { mmToPx($0.x, $0.y, size: texSize) }
        } else {
            boundaryPts = nil
        }

        let renderer = UIGraphicsImageRenderer(size: texSize)
        let tex = renderer.image { ctx in
            let gc = ctx.cgContext

            // 背景（透明）
            gc.clear(CGRect(origin: .zero, size: texSize))

            // フロア外枠でクリッピング（図面もヒートマップも外枠の内側のみ表示）
            if let pts = boundaryPts {
                gc.saveGState()
                gc.beginPath()
                for (i, pt) in pts.enumerated() {
                    if i == 0 { gc.move(to: pt) } else { gc.addLine(to: pt) }
                }
                gc.closePath()
                gc.clip()
            }

            // 背景色（外枠内のみ）
            UIColor(white: 0.15, alpha: 1).setFill()
            gc.fill(CGRect(origin: .zero, size: texSize))

            // 図面（外枠内のみ）
            coord.floorImage?.draw(in: CGRect(origin: .zero, size: texSize))

            // ヒートマップ（9点IDW補間、外枠内のみ）
            drawHeatmap(gc: gc, size: texSize, piLocs: piLocs)

            if boundaryPts != nil { gc.restoreGState() }
        }

        // 床面プレーン
        let floorNode: SCNNode
        if let existing = scene.rootNode.childNode(withName: "floor", recursively: false) {
            floorNode = existing
        } else {
            let cal = appConfig?.CALIBRATION
            let oX = cal?.origin_px?.x ?? 116.25
            let oY = cal?.origin_px?.y ?? 340.75
            let sc = cal?.scale_mm_per_px ?? 6.335
            let s = Self.S

            let mmW = imgW * sc, mmH = imgH * sc
            let plane = SCNPlane(width: CGFloat(Float(mmW) * s), height: CGFloat(Float(mmH) * s))
            plane.firstMaterial?.isDoubleSided = true
            plane.firstMaterial?.lightingModel = .constant
            plane.firstMaterial?.transparencyMode = .aOne  // テクスチャの透明部分を透過

            floorNode = SCNNode(geometry: plane)
            floorNode.name = "floor"
            floorNode.eulerAngles.x = -.pi / 2

            // 画像の物理座標範囲の中心
            let xMin = (0 - oX) * sc, xMax = (imgW - oX) * sc
            let yMin = -(imgH - oY) * sc, yMax = -(0 - oY) * sc
            let cx = Float((xMin + xMax) / 2) * s
            let cz = Float((yMin + yMax) / 2) * s
            floorNode.position = SCNVector3(cx, -0.001, cz)

            print("[3D] 床面作成: center=(\(cx), \(cz)), size=(\(Float(mmW)*s), \(Float(mmH)*s))")
            print("[3D] 物理範囲: X[\(xMin)...\(xMax)], Y[\(yMin)...\(yMax)]")

            scene.rootNode.addChildNode(floorNode)
        }

        // テクスチャ設定 — contentsTransform は不要
        // SCNPlaneをX軸-90度で倒した状態では、UIImageのデフォルトUVがそのまま正しくマッピングされる
        floorNode.geometry?.firstMaterial?.diffuse.contents = tex
        floorNode.geometry?.firstMaterial?.diffuse.contentsTransform = SCNMatrix4Identity
    }

    // MARK: - ヒートマップ描画（FLOOR_BOUNDARY内部のみ）
    private func drawHeatmap(gc: CGContext, size: CGSize, piLocs: [(id: String, x: Double, y: Double)]) {
        let readings = sensorData
        guard !readings.isEmpty, piLocs.count >= 2 else { return }

        let posMap = Dictionary(piLocs.map { ($0.id, ($0.x, $0.y)) }, uniquingKeysWith: { a, _ in a })
        let matched = readings.filter { posMap[$0.id] != nil }.count
        print("[3D] ヒートマップ: readings=\(readings.count), piLocs=\(piLocs.count), マッチ=\(matched)")

        // FLOOR_BOUNDARYクリッピングパス
        let bdPoints: [CGPoint]?
        if let bd = appConfig?.FLOOR_BOUNDARY, bd.count >= 3 {
            bdPoints = bd.map { mmToPx($0.x, $0.y, size: size) }
        } else {
            bdPoints = nil
        }

        if let pts = bdPoints {
            gc.saveGState()
            gc.beginPath()
            for (i, pt) in pts.enumerated() {
                if i == 0 { gc.move(to: pt) } else { gc.addLine(to: pt) }
            }
            gc.closePath()
            gc.clip()
        }

        let bounds = floorBoundsMm()
        let values = readings.compactMap { $0.value(for: sensor) }
        guard let rawMin = values.min(), let rawMax = values.max() else {
            if bdPoints != nil { gc.restoreGState() }
            return
        }
        let range = rawMax - rawMin
        let margin = range > 0 ? range * 0.05 : 1.0
        let vMin = rawMin - margin, vMax = rawMax + margin

        let gW = 40, gH = 40  // 解像度最適化: 80x80→40x40（描画負荷1/4、見た目はほぼ同等）
        let cellW = size.width / CGFloat(gW), cellH = size.height / CGFloat(gH)

        for row in 0..<gH {
            for col in 0..<gW {
                let physX = bounds.xMin + (Double(col) + 0.5) / Double(gW) * (bounds.xMax - bounds.xMin)
                let physY = bounds.yMin + (Double(row) + 0.5) / Double(gH) * (bounds.yMax - bounds.yMin)

                let val = idwInterpolate(x: physX, y: physY, readings: readings, piLocs: piLocs)
                guard val.isFinite else { continue }

                let t = max(0, min(1, (val - vMin) / (vMax - vMin)))
                let (r, g, b) = colorRGB(sensor: sensor, t: t)
                gc.setFillColor(red: r, green: g, blue: b, alpha: 0.55)
                gc.fill(CGRect(x: CGFloat(col) * cellW, y: CGFloat(row) * cellH, width: cellW + 0.5, height: cellH + 0.5))
            }
        }

        if bdPoints != nil { gc.restoreGState() }
    }

    // MARK: - 人マーカー（人モデル + プロフィールアイコン + 名前ラベル + 動静表現）
    private func updatePersons(scene: SCNScene, coord: Coordinator) {
        scene.rootNode.childNodes.filter { $0.name?.hasPrefix("p_") == true }.forEach { $0.removeFromParentNode() }
        scene.rootNode.childNodes.filter { $0.name?.hasPrefix("hl_") == true }.forEach { $0.removeFromParentNode() }

        let s = Self.S
        for p in persons {
            guard let ex = p.estimated_x, let ey = p.estimated_y else { continue }
            let posX = Float(ex) * s, posZ = Float(ey) * s
            let moving = p.is_moving ?? false

            let parent = SCNNode()
            parent.name = "p_\(p.id)"
            parent.position = SCNVector3(posX, 0, posZ)
            scene.rootNode.addChildNode(parent)

            // ステータス色
            let statusColor: UIColor
            switch p.status {
            case "focused": statusColor = .systemRed
            case "busy": statusColor = .systemOrange
            default: statusColor = .systemGreen
            }

            // --- リアルな人体モデル ---
            // 座った状態: 約1100mm、立った状態(移動中): 約1700mm
            let skinColor = UIColor(red: 0.96, green: 0.84, blue: 0.74, alpha: 1.0)
            let headR: Float = 0.10

            if moving {
                // === 立位（移動中）===
                let torsoH: Float = 0.55, torsoR: Float = 0.14
                let legH: Float = 0.75, legR: Float = 0.06
                let armH: Float = 0.50, armR: Float = 0.045
                let hipY: Float = legH
                let shoulderY: Float = hipY + torsoH
                let headY: Float = shoulderY + headR + 0.03

                // 胴体（低ポリゴン）
                let torso = SCNCapsule(capRadius: CGFloat(torsoR), height: CGFloat(torsoH))
                torso.radialSegmentCount = 12
                torso.heightSegmentCount = 1
                torso.firstMaterial?.diffuse.contents = statusColor.withAlphaComponent(0.9)
                let torsoNode = SCNNode(geometry: torso)
                torsoNode.position = SCNVector3(0, hipY + torsoH / 2, 0)
                parent.addChildNode(torsoNode)

                // 頭（低ポリゴン）
                let head = SCNSphere(radius: CGFloat(headR))
                head.segmentCount = 12
                head.firstMaterial?.diffuse.contents = skinColor
                let headNode = SCNNode(geometry: head)
                headNode.position = SCNVector3(0, headY, 0)
                parent.addChildNode(headNode)

                // 左脚
                let legGeo = SCNCapsule(capRadius: CGFloat(legR), height: CGFloat(legH))
                legGeo.radialSegmentCount = 8
                legGeo.heightSegmentCount = 1
                legGeo.firstMaterial?.diffuse.contents = UIColor(white: 0.25, alpha: 1)
                let leftLeg = SCNNode(geometry: legGeo)
                leftLeg.position = SCNVector3(-0.06, legH / 2, 0)
                parent.addChildNode(leftLeg)
                // 右脚
                let rightLeg = SCNNode(geometry: legGeo.copy() as! SCNGeometry)
                rightLeg.position = SCNVector3(0.06, legH / 2, 0)
                parent.addChildNode(rightLeg)

                // 左腕（少し開く、低ポリゴン）
                let armGeo = SCNCapsule(capRadius: CGFloat(armR), height: CGFloat(armH))
                armGeo.radialSegmentCount = 8
                armGeo.heightSegmentCount = 1
                armGeo.firstMaterial?.diffuse.contents = statusColor.withAlphaComponent(0.75)
                let leftArm = SCNNode(geometry: armGeo)
                leftArm.position = SCNVector3(-torsoR - armR - 0.01, shoulderY - armH / 2 + 0.02, 0)
                leftArm.eulerAngles = SCNVector3(0, 0, Float.pi * 0.05)
                parent.addChildNode(leftArm)
                // 右腕
                let rightArm = SCNNode(geometry: armGeo.copy() as! SCNGeometry)
                rightArm.position = SCNVector3(torsoR + armR + 0.01, shoulderY - armH / 2 + 0.02, 0)
                rightArm.eulerAngles = SCNVector3(0, 0, -Float.pi * 0.05)
                parent.addChildNode(rightArm)

                let topY = headY + headR  // 頭頂

                // パルスリング（足元の波紋）
                let ring = SCNTorus(ringRadius: 0.3, pipeRadius: 0.02)
                ring.firstMaterial?.diffuse.contents = UIColor.systemYellow
                ring.firstMaterial?.transparency = 0.7
                let ringNode = SCNNode(geometry: ring)
                ringNode.position = SCNVector3(0, 0.01, 0)
                parent.addChildNode(ringNode)

                let scaleAnim = CABasicAnimation(keyPath: "scale")
                scaleAnim.fromValue = NSValue(scnVector3: SCNVector3(1, 1, 1))
                scaleAnim.toValue = NSValue(scnVector3: SCNVector3(2.5, 1, 2.5))
                scaleAnim.duration = 1.5
                scaleAnim.repeatCount = .infinity
                ringNode.addAnimation(scaleAnim, forKey: "pulse_scale")

                let fadeAnim = CABasicAnimation(keyPath: "opacity")
                fadeAnim.fromValue = 0.7
                fadeAnim.toValue = 0.0
                fadeAnim.duration = 1.5
                fadeAnim.repeatCount = .infinity
                ringNode.addAnimation(fadeAnim, forKey: "pulse_fade")

                // 上下バウンス
                let bounce = CABasicAnimation(keyPath: "position.y")
                bounce.fromValue = parent.position.y
                bounce.toValue = parent.position.y + 0.06
                bounce.duration = 0.5
                bounce.autoreverses = true
                bounce.repeatCount = .infinity
                bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                parent.addAnimation(bounce, forKey: "bounce")

                // 移動中ラベル — X方向にオフセットして重ならないように
                let moveLb = billboardLabel("移動中", size: 22, bg: UIColor.systemYellow.withAlphaComponent(0.9), scale: 0.005)
                moveLb.position = SCNVector3(0.35, topY - 0.1, 0.15)
                parent.addChildNode(moveLb)

                // プロフィールアイコン
                let avatarSize: CGFloat = 100
                let avatarImg = makeAvatarImage(
                    profileImage: coord.profileImages[p.beacon_id],
                    name: p.user_name ?? "?",
                    status: p.status,
                    size: avatarSize
                )
                let avatarPlane = SCNPlane(width: 0.7, height: 0.7)
                avatarPlane.firstMaterial?.diffuse.contents = avatarImg
                avatarPlane.firstMaterial?.lightingModel = .constant
                avatarPlane.firstMaterial?.isDoubleSided = true
                let avatarNode = SCNNode(geometry: avatarPlane)
                avatarNode.position = SCNVector3(0, topY + 0.20, 0)
                avatarNode.constraints = [SCNBillboardConstraint()]
                parent.addChildNode(avatarNode)

                // 名前ラベル
                let displayName = p.user_name ?? String(p.beacon_id.prefix(6))
                let lb = billboardLabel(displayName, size: 26, bg: .systemBlue, scale: 0.007)
                lb.position = SCNVector3(0, topY + 0.60, 0)
                parent.addChildNode(lb)

            } else {
                // === 座位（静止中、低ポリゴン）===
                let torsoH: Float = 0.40, torsoR: Float = 0.14
                let thighH: Float = 0.35, thighR: Float = 0.065
                let lowerLegH: Float = 0.38, lowerLegR: Float = 0.055
                let armH: Float = 0.35, armR: Float = 0.04
                let seatY: Float = lowerLegH
                let shoulderY: Float = seatY + torsoH
                let headY: Float = shoulderY + headR + 0.03

                // 胴体
                let torso = SCNCapsule(capRadius: CGFloat(torsoR), height: CGFloat(torsoH))
                torso.radialSegmentCount = 12
                torso.heightSegmentCount = 1
                torso.firstMaterial?.diffuse.contents = statusColor.withAlphaComponent(0.9)
                let torsoNode = SCNNode(geometry: torso)
                torsoNode.position = SCNVector3(0, seatY + torsoH / 2, 0)
                parent.addChildNode(torsoNode)

                // 頭
                let head = SCNSphere(radius: CGFloat(headR))
                head.segmentCount = 12
                head.firstMaterial?.diffuse.contents = skinColor
                let headNode = SCNNode(geometry: head)
                headNode.position = SCNVector3(0, headY, 0)
                parent.addChildNode(headNode)

                // 太もも（水平に前方へ伸ばす、低ポリゴン）
                let thighGeo = SCNCapsule(capRadius: CGFloat(thighR), height: CGFloat(thighH))
                thighGeo.radialSegmentCount = 8
                thighGeo.heightSegmentCount = 1
                thighGeo.firstMaterial?.diffuse.contents = UIColor(white: 0.25, alpha: 1)
                let leftThigh = SCNNode(geometry: thighGeo)
                leftThigh.position = SCNVector3(-0.06, seatY, thighH / 2 - 0.05)
                leftThigh.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
                parent.addChildNode(leftThigh)
                let rightThigh = SCNNode(geometry: thighGeo.copy() as! SCNGeometry)
                rightThigh.position = SCNVector3(0.06, seatY, thighH / 2 - 0.05)
                rightThigh.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
                parent.addChildNode(rightThigh)

                // すね（垂直に下へ、低ポリゴン）
                let lowerGeo = SCNCapsule(capRadius: CGFloat(lowerLegR), height: CGFloat(lowerLegH))
                lowerGeo.radialSegmentCount = 8
                lowerGeo.heightSegmentCount = 1
                lowerGeo.firstMaterial?.diffuse.contents = UIColor(white: 0.25, alpha: 1)
                let leftLower = SCNNode(geometry: lowerGeo)
                leftLower.position = SCNVector3(-0.06, lowerLegH / 2, thighH - 0.05)
                parent.addChildNode(leftLower)
                let rightLower = SCNNode(geometry: lowerGeo.copy() as! SCNGeometry)
                rightLower.position = SCNVector3(0.06, lowerLegH / 2, thighH - 0.05)
                parent.addChildNode(rightLower)

                // 腕（前方に机に向かって伸ばす、低ポリゴン）
                let armGeo = SCNCapsule(capRadius: CGFloat(armR), height: CGFloat(armH))
                armGeo.radialSegmentCount = 8
                armGeo.heightSegmentCount = 1
                armGeo.firstMaterial?.diffuse.contents = statusColor.withAlphaComponent(0.7)
                let leftArm = SCNNode(geometry: armGeo)
                leftArm.position = SCNVector3(-torsoR - armR, shoulderY - 0.08, armH / 2 - 0.08)
                leftArm.eulerAngles = SCNVector3(Float.pi * 0.35, 0, 0)
                parent.addChildNode(leftArm)
                let rightArm = SCNNode(geometry: armGeo.copy() as! SCNGeometry)
                rightArm.position = SCNVector3(torsoR + armR, shoulderY - 0.08, armH / 2 - 0.08)
                rightArm.eulerAngles = SCNVector3(Float.pi * 0.35, 0, 0)
                parent.addChildNode(rightArm)

                let topY = headY + headR

                // 静止中リング
                let ring = SCNTorus(ringRadius: 0.2, pipeRadius: 0.015)
                ring.firstMaterial?.diffuse.contents = UIColor.systemCyan.withAlphaComponent(0.4)
                let ringNode = SCNNode(geometry: ring)
                ringNode.position = SCNVector3(0, 0.01, 0)
                parent.addChildNode(ringNode)

                // 静止中ラベル — X方向にオフセット
                let stillLb = billboardLabel("静止中", size: 22, bg: UIColor.systemCyan.withAlphaComponent(0.85), scale: 0.005)
                stillLb.position = SCNVector3(0.35, topY - 0.1, 0.15)
                parent.addChildNode(stillLb)

                // プロフィールアイコン
                let avatarSize: CGFloat = 100
                let avatarImg = makeAvatarImage(
                    profileImage: coord.profileImages[p.beacon_id],
                    name: p.user_name ?? "?",
                    status: p.status,
                    size: avatarSize
                )
                let avatarPlane = SCNPlane(width: 0.7, height: 0.7)
                avatarPlane.firstMaterial?.diffuse.contents = avatarImg
                avatarPlane.firstMaterial?.lightingModel = .constant
                avatarPlane.firstMaterial?.isDoubleSided = true
                let avatarNode = SCNNode(geometry: avatarPlane)
                avatarNode.position = SCNVector3(0, topY + 0.20, 0)
                avatarNode.constraints = [SCNBillboardConstraint()]
                parent.addChildNode(avatarNode)

                // 名前ラベル
                let displayName = p.user_name ?? String(p.beacon_id.prefix(6))
                let lb = billboardLabel(displayName, size: 26, bg: .systemBlue, scale: 0.007)
                lb.position = SCNVector3(0, topY + 0.60, 0)
                parent.addChildNode(lb)
            }

            // プロフィール画像の非同期読込
            if coord.profileImages[p.beacon_id] == nil, let imgPath = p.profile_image {
                loadProfileImage(beaconId: p.beacon_id, path: imgPath, coord: coord)
            }
        }

        // ハイライト表示
        if let target = highlightTarget,
           let ex = persons.first(where: { $0.beacon_id == target.beaconId })?.estimated_x ?? target.x,
           let ey = persons.first(where: { $0.beacon_id == target.beaconId })?.estimated_y ?? target.y {
            let hx = Float(ex) * s, hz = Float(ey) * s
            addHighlightRing(scene: scene, x: hx, z: hz, userName: target.userName)
        }
    }

    // MARK: - プロフィール画像読込（ImageCacheManager経由）
    private func loadProfileImage(beaconId: String, path: String, coord: Coordinator) {
        guard let url = URL(string: ServerConfig.baseURL + path) else { return }
        Task {
            if let img = await ImageCacheManager.shared.loadImage(from: url) {
                await MainActor.run {
                    coord.profileImages[beaconId] = img
                    if let scene = coord.scnView?.scene {
                        updatePersons(scene: scene, coord: coord)
                    }
                }
            } else {
                print("[3D] プロフィール画像読込失敗: \(beaconId)")
            }
        }
    }

    // MARK: - アバター画像生成（円形 + ステータスランプ）
    private func makeAvatarImage(profileImage: UIImage?, name: String, status: String?, size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let gc = ctx.cgContext
            let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))
            let circlePath = UIBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3))

            // 背景を透明に
            gc.clear(rect)

            // 円形クリップ
            gc.saveGState()
            circlePath.addClip()

            if let img = profileImage {
                img.draw(in: rect.insetBy(dx: 3, dy: 3))
            } else {
                // 頭文字プレースホルダー
                UIColor(red: 0.3, green: 0.3, blue: 0.6, alpha: 1).setFill()
                UIBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).fill()
                let initial = String(name.prefix(1)).uppercased()
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: size * 0.4, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                let ts = (initial as NSString).size(withAttributes: attrs)
                (initial as NSString).draw(
                    at: CGPoint(x: (size - ts.width) / 2, y: (size - ts.height) / 2),
                    withAttributes: attrs
                )
            }
            gc.restoreGState()

            // 円枠
            UIColor.white.setStroke()
            circlePath.lineWidth = 3
            circlePath.stroke()

            // ステータスランプ（右下）
            let lampSize: CGFloat = size * 0.25
            let lampRect = CGRect(x: size - lampSize - 2, y: size - lampSize - 2, width: lampSize, height: lampSize)
            let lampColor: UIColor
            switch status {
            case "focused": lampColor = .systemRed
            case "busy": lampColor = .systemOrange
            default: lampColor = .systemGreen
            }
            lampColor.setFill()
            UIBezierPath(ovalIn: lampRect).fill()
            UIColor.white.setStroke()
            let lampPath = UIBezierPath(ovalIn: lampRect)
            lampPath.lineWidth = 2
            lampPath.stroke()
        }
    }

    // MARK: - おすすめゾーン表示（空中フレーム方式 — 床面テクスチャを隠さない）
    private func updateRecommendationZone(scene: SCNScene) {
        // 既存のゾーンノードを削除
        scene.rootNode.childNodes
            .filter { $0.name?.hasPrefix("rz_") == true }
            .forEach { $0.removeFromParentNode() }

        let s = Self.S
        let zones = appConfig?.ZONE_BOUNDARIES ?? [:]
        let bestZone = recommendation?.best_zone

        // ZONE_BOUNDARIES の Y座標は正値（Leaflet/旧座標系）
        // 物理座標系（SceneKit Z軸）では Y は負値なので符号反転が必要
        // 壁と同じ高さ (2800mm)
        let wallH: Float = 2800 * s

        for (name, boundary) in zones {
            let isBest = name == bestZone
            let xMin = Float(boundary.x_min) * s
            let xMax = Float(boundary.x_max) * s
            let zMin = Float(-boundary.y_max) * s
            let zMax = Float(-boundary.y_min) * s
            let w = xMax - xMin
            let d = zMax - zMin
            let cx = (xMin + xMax) / 2
            let cz = (zMin + zMax) / 2

            if isBest {
                // 推奨ゾーン: 緑フレーム
                let frame = makeZoneFrame(
                    xMin: xMin, zMin: zMin, xMax: xMax, zMax: zMax,
                    height: wallH,
                    color: UIColor.systemGreen,
                    postRadius: 0.04, barRadius: 0.025
                )
                frame.name = "rz_best_frame"
                frame.castsShadow = false
                frame.enumerateChildNodes { child, _ in child.castsShadow = false }
                scene.rootNode.addChildNode(frame)

                // パルスアニメーション
                let fadeOut = SCNAction.fadeOpacity(to: 0.4, duration: 1.0)
                let fadeIn = SCNAction.fadeOpacity(to: 1.0, duration: 1.0)
                frame.runAction(SCNAction.repeatForever(SCNAction.sequence([fadeOut, fadeIn])))

                // ゾーン名ラベル（非推奨と同サイズ）
                let lb = billboardLabel("★ \(name)", size: 30, bg: UIColor.systemGreen.withAlphaComponent(0.85), scale: 0.011)
                lb.name = "rz_best_label"
                lb.castsShadow = false
                lb.position = SCNVector3(cx, wallH + 0.3, cz)
                scene.rootNode.addChildNode(lb)
            
            } else {
                // 非推奨ゾーン: 半透明グレーフレーム
                let frame = makeZoneFrame(
                    xMin: xMin, zMin: zMin, xMax: xMax, zMax: zMax,
                    height: wallH,
                    color: UIColor.systemGray.withAlphaComponent(0.7),
                    postRadius: 0.025, barRadius: 0.015
                )
                frame.name = "rz_zone_\(name)"
                frame.castsShadow = false
                frame.enumerateChildNodes { child, _ in child.castsShadow = false }
                scene.rootNode.addChildNode(frame)

                // ゾーン名ラベル
                let lb = billboardLabel(name, size: 30, bg: UIColor.systemGray.withAlphaComponent(0.7), scale: 0.011)
                lb.name = "rz_label_\(name)"
                lb.castsShadow = false
                lb.position = SCNVector3(cx, wallH + 0.3, cz)
                scene.rootNode.addChildNode(lb)
            }
        }
    }

    /// 空中フレームを構築
    private func makeZoneFrame(xMin: Float, zMin: Float, xMax: Float, zMax: Float,
                               height: Float, color: UIColor,
                               postRadius: Float, barRadius: Float) -> SCNNode {
        let parent = SCNNode()
        let w = xMax - xMin
        let d = zMax - zMin
        let barThick = barRadius * 2

        // コーナーポスト（垂直シリンダー）4本
        let postGeo = SCNCylinder(radius: CGFloat(postRadius), height: CGFloat(height))
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.lightingModel = .constant
        postGeo.materials = [mat]

        let cornerXZ: [(Float, Float)] = [
            (xMin, zMin), (xMax, zMin), (xMax, zMax), (xMin, zMax)
        ]
        for (px, pz) in cornerXZ {
            let post = SCNNode(geometry: postGeo)
            post.position = SCNVector3(px, height / 2, pz)
            parent.addChildNode(post)
        }

        // 上部水平バー4本（SCNBoxで軸揃え — 回転不要）
        let barMat = SCNMaterial()
        barMat.diffuse.contents = color
        barMat.lightingModel = .constant

        // X方向のバー2本（手前・奥）
        for bz in [zMin, zMax] {
            let barGeo = SCNBox(width: CGFloat(w), height: CGFloat(barThick), length: CGFloat(barThick), chamferRadius: 0)
            barGeo.materials = [barMat]
            let bar = SCNNode(geometry: barGeo)
            bar.position = SCNVector3((xMin + xMax) / 2, height, bz)
            parent.addChildNode(bar)
        }
        // Z方向のバー2本（左・右）
        for bx in [xMin, xMax] {
            let barGeo = SCNBox(width: CGFloat(barThick), height: CGFloat(barThick), length: CGFloat(d), chamferRadius: 0)
            barGeo.materials = [barMat]
            let bar = SCNNode(geometry: barGeo)
            bar.position = SCNVector3(bx, height, (zMin + zMax) / 2)
            parent.addChildNode(bar)
        }

        return parent
    }



    // MARK: - ハイライトリング
    private func addHighlightRing(scene: SCNScene, x: Float, z: Float, userName: String?) {
        // 空中に浮かぶパルスリング（人の頭上付近 Y=1.5m）
        let airY: Float = 1.5

        // 外側リング（パルス拡大+フェード）
        let outerRing = SCNTorus(ringRadius: 0.5, pipeRadius: 0.025)
        outerRing.firstMaterial?.diffuse.contents = UIColor.systemYellow.withAlphaComponent(0.7)
        outerRing.firstMaterial?.lightingModel = .constant
        let outerNode = SCNNode(geometry: outerRing)
        outerNode.name = "hl_outer"
        outerNode.position = SCNVector3(x, airY, z)
        scene.rootNode.addChildNode(outerNode)

        // 内側リング（固定サイズ）
        let innerRing = SCNTorus(ringRadius: 0.35, pipeRadius: 0.035)
        innerRing.firstMaterial?.diffuse.contents = UIColor.systemYellow
        innerRing.firstMaterial?.lightingModel = .constant
        let innerNode = SCNNode(geometry: innerRing)
        innerNode.name = "hl_inner"
        innerNode.position = SCNVector3(x, airY, z)
        scene.rootNode.addChildNode(innerNode)

        // 外側リングのパルスアニメーション（拡大+フェード）
        let scaleAnim = CABasicAnimation(keyPath: "scale")
        scaleAnim.fromValue = NSValue(scnVector3: SCNVector3(1, 1, 1))
        scaleAnim.toValue = NSValue(scnVector3: SCNVector3(2.0, 1, 2.0))
        scaleAnim.duration = 1.2
        scaleAnim.repeatCount = .infinity
        outerNode.addAnimation(scaleAnim, forKey: "hl_scale")

        let fadeAnim = CABasicAnimation(keyPath: "opacity")
        fadeAnim.fromValue = 0.8
        fadeAnim.toValue = 0.0
        fadeAnim.duration = 1.2
        fadeAnim.repeatCount = .infinity
        outerNode.addAnimation(fadeAnim, forKey: "hl_fade")

        // 内側リングの上下バウンス
        let bounce = CABasicAnimation(keyPath: "position.y")
        bounce.fromValue = airY
        bounce.toValue = airY + 0.15
        bounce.duration = 0.8
        bounce.autoreverses = true
        bounce.repeatCount = .infinity
        bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        innerNode.addAnimation(bounce, forKey: "hl_bounce")

        // 下方向への矢印ライン（対象の位置を指し示す）
        let lineGeo = SCNCylinder(radius: 0.015, height: CGFloat(airY))
        lineGeo.firstMaterial?.diffuse.contents = UIColor.systemYellow.withAlphaComponent(0.4)
        lineGeo.firstMaterial?.lightingModel = .constant
        let lineNode = SCNNode(geometry: lineGeo)
        lineNode.name = "hl_line"
        lineNode.position = SCNVector3(x, airY / 2, z)
        scene.rootNode.addChildNode(lineNode)

        // ハイライト対象の名前ラベル（リングの上方）
        if let name = userName {
            let lb = billboardLabel("📍 " + name, size: 30, bg: UIColor.systemYellow.withAlphaComponent(0.9), scale: 0.008)
            lb.name = "hl_label"
            lb.position = SCNVector3(x, airY + 0.45, z)
            scene.rootNode.addChildNode(lb)
        }
    }

    // MARK: - 座標変換（2DのmmToViewPointと完全同一）
    private func mmToPx(_ mmX: Double, _ mmY: Double, size: CGSize) -> CGPoint {
        let cal = appConfig?.CALIBRATION
        let imgW = appConfig?.FLOORPLAN_IMAGE?.width ?? 1483
        let imgH = appConfig?.FLOORPLAN_IMAGE?.height ?? 1753
        let oX = cal?.origin_px?.x ?? 116.25
        let oY = cal?.origin_px?.y ?? 340.75
        let sc = cal?.scale_mm_per_px ?? 6.335

        let pxX = mmX / sc + oX
        let pxY = imgH - (-mmY / sc + oY)
        return CGPoint(x: pxX / imgW * size.width, y: pxY / imgH * size.height)
    }

    // MARK: - 物理座標範囲（2Dと同一）
    private func floorBoundsMm() -> (xMin: Double, xMax: Double, yMin: Double, yMax: Double) {
        let cal = appConfig?.CALIBRATION
        let imgW = appConfig?.FLOORPLAN_IMAGE?.width ?? 1483
        let imgH = appConfig?.FLOORPLAN_IMAGE?.height ?? 1753
        let oX = cal?.origin_px?.x ?? 116.25
        let oY = cal?.origin_px?.y ?? 340.75
        let sc = cal?.scale_mm_per_px ?? 6.335
        return (
            (0 - oX) * sc,
            (imgW - oX) * sc,
            -(imgH - oY) * sc,
            -(0 - oY) * sc
        )
    }

    // MARK: - Pi位置（2Dと同一）
    private func piPositions() -> [(id: String, x: Double, y: Double)] {
        if let locs = appConfig?.PI_LOCATIONS, !locs.isEmpty {
            return locs.map { (id: $0.piId, x: $0.x, y: $0.y) }
        }
        return BeaconConfig.coordinates.sorted { $0.key < $1.key }.map {
            (id: String(format: "ras_%02d", $0.key), x: $0.value.y, y: -$0.value.x)
        }
    }

    // MARK: - IDW補間（2Dと同一）
    private func idwInterpolate(x: Double, y: Double, readings: [SensorReading], piLocs: [(id: String, x: Double, y: Double)]) -> Double {
        let posMap = Dictionary(piLocs.map { ($0.id, ($0.x, $0.y)) }, uniquingKeysWith: { a, _ in a })
        var wSum = 0.0, vSum = 0.0
        for r in readings {
            let v = r.value(for: sensor)
            guard let pos = posMap[r.id] else { continue }
            let d = sqrt(pow(x - pos.0, 2) + pow(y - pos.1, 2))
            if d < 1 { return v }
            let w = 1.0 / (d * d)
            wSum += w; vSum += w * v
        }
        return wSum > 0 ? vSum / wSum : .nan
    }

    // MARK: - カラーマップ（2Dと同一）
    private func colorRGB(sensor: SensorType, t: Double) -> (CGFloat, CGFloat, CGFloat) {
        let stops: [(Double, Double, Double, Double)]
        switch sensor {
        case .temp:
            stops = [(0,0,0,0.6),(0.2,0,0.5,1),(0.4,0,0.8,0.4),(0.6,1,1,0),(0.8,1,0.5,0),(1,0.8,0,0)]
        case .humidity:
            stops = [(0,0.9,0.9,0.5),(0.5,0.3,0.6,0.9),(1,0,0.1,0.6)]
        case .lux:
            stops = [(0,0.15,0,0.3),(0.5,0.8,0.5,0.1),(1,1,1,0.3)]
        case .co2:
            stops = [(0,0.1,0.7,0.2),(0.5,0.9,0.8,0.1),(1,0.8,0.1,0.1)]
        }
        for i in 0..<stops.count - 1 {
            if t >= stops[i].0 && t <= stops[i+1].0 {
                let f = (t - stops[i].0) / (stops[i+1].0 - stops[i].0)
                return (
                    CGFloat(stops[i].1 + f * (stops[i+1].1 - stops[i].1)),
                    CGFloat(stops[i].2 + f * (stops[i+1].2 - stops[i].2)),
                    CGFloat(stops[i].3 + f * (stops[i+1].3 - stops[i].3))
                )
            }
        }
        let l = stops.last!
        return (CGFloat(l.1), CGFloat(l.2), CGFloat(l.3))
    }

    // MARK: - hex色文字列 → UIColor
    private static func uiColorFromHex(_ hex: String) -> UIColor? {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        let r = CGFloat((val >> 16) & 0xFF) / 255
        let g = CGFloat((val >> 8) & 0xFF) / 255
        let b = CGFloat(val & 0xFF) / 255
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }
}
