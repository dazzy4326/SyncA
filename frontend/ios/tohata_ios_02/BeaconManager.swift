//
//  BeaconManager.swift
//  tohata_ios_02
//
//  Created by daichi0208 on 2025/11/13.
//

import Foundation
import CoreLocation
import Combine
import UIKit
import CoreMotion
import Accelerate
import Network
import UserNotifications

class BeaconManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    
    /*
     * 測位ロジックの切り替え
     * true: 【サーバー計算 (Shapely)】
     * false: 【iPhone計算 (LSM)】
     */
    private let useServerSideShapely: Bool = true
    
    
    // (B) @Published プロパティ
    @Published var estimatedPosition: (x: Double, y: Double)? = nil
    @Published var logMessage: String = "マネージャーを初期化中..."

    // 測位ステータス (UI用)
    enum PositioningPhase: String {
        case initializing = "初期化中"
        case scanning = "ビーコンスキャン中"
        case collecting = "サンプル収集中"
        case calculating = "測位計算中"
        case positioned = "測位完了"
        case movingSkipped = "移動中（スキップ）"
        case insufficientBeacons = "ビーコン不足"
    }
    @Published var positioningPhase: PositioningPhase = .initializing
    @Published var beaconSampleProgress: [Int: (current: Int, required: Int)] = [:]
    @Published var medianReadyCount: Int = 0
    @Published var lastPositionedAt: Date? = nil
    
    @Published var isServerConnected: Bool = true

    // 現在BLE検出中のビーコン (minor ID セット)
    @Published var activeBeaconMinors: Set<Int> = []
    
    @Published var showWifiAlert: Bool = false
    @Published var wifiAlertMessage: String = ""
    
    /// デバイス固有ID (一度だけ取得してキャッシュ)
    let deviceID: String = UIDevice.current.identifierForVendor?.uuidString ?? "unknown_device"

    private var isAlertSuppressed: Bool = false
    
    @Published var showSuccessAlert: Bool = false
    @Published var successMessage: String = ""
    
    // 前回の接続状態を記録 (false = 未接続/エラー, true = 接続中)
    private var wasConnected: Bool = false
    
    @Published var currentUserName: String = UserDefaultsConfig.defaultUserName
    
    @Published var currentJobTitle: String = UserDefaultsConfig.defaultJobTitle
    @Published var currentDepartment: String = UserDefaultsConfig.defaultDepartment
    @Published var currentStatus: String = UserDefaultsConfig.defaultStatus
    
    private let isSnappingEnabled: Bool = false       // マップスナップ無効化
    private let isDetailedLoggingEnabled: Bool = true //  詳細ロギングのトグル
    
    private var locationManager: CLLocationManager!
    
    private var networkMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")

    // ビーコンの座標 (mm単位) (9台グリッド)
    private let beaconCoordinates = BeaconConfig.coordinates
    
    private let targetUUID = BeaconConfig.targetUUID
    
    // ---動静検知用のプロパティ---
    private var motionManager: CMMotionManager!
    private var motionTimer: Timer?
    private let motionInterval = SensorConfig.kfInterval
    @Published var isUserMoving: Bool = false
    private let motionThreshold = SensorConfig.motionThreshold
    
    // --- バックグラウンドBLE監視 ---
    private var beaconRegion: CLBeaconRegion!
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var isInBackground: Bool = false

    // --- サンプリング ---
    private var beaconSampleBuffers: [Int: [Double]] = [:]
    private var medianDistances: [Int: Double] = [:]
    private let sampleCount = BeaconConfig.sampleCount

    /// フォアグラウンド/バックグラウンドに応じたサンプル数
    private var currentSampleCount: Int {
        isInBackground ? BeaconConfig.backgroundSampleCount : sampleCount
    }
    
    override init() {
        super.init()

        startNetworkMonitoring()
        locationManager = CLLocationManager()
        locationManager.delegate = self

        motionManager = CMMotionManager()
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = motionInterval
            motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        }

        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.requestAlwaysAuthorization()

        // バックグラウンドBLE監視用のリージョンを設定
        beaconRegion = CLBeaconRegion(uuid: targetUUID, identifier: "TohataBeaconRegion")
        beaconRegion.notifyOnEntry = true
        beaconRegion.notifyOnExit = true
        beaconRegion.notifyEntryStateOnDisplay = true

        // アプリのフォアグラウンド/バックグラウンド状態を監視
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)

        startMotionDetectionLoop()
    }

    @objc private func appDidEnterBackground() {
        isInBackground = true
        // バックグラウンド移行時にバッファをクリアして少ないサンプル数で再収集
        beaconSampleBuffers.removeAll()
        medianDistances.removeAll()
        print("[BG] バックグラウンドに移行。サンプル数を\(currentSampleCount)に切り替えます。")
    }

    @objc private func appWillEnterForeground() {
        isInBackground = false
        // フォアグラウンド復帰時にバッファをクリアして通常サンプル数で再収集
        beaconSampleBuffers.removeAll()
        medianDistances.removeAll()
        print("[BG] フォアグラウンドに復帰。サンプル数を\(currentSampleCount)に戻します。")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        motionTimer?.invalidate()
        motionTimer = nil
        networkMonitor?.cancel()
        networkMonitor = nil
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        locationManager.stopMonitoring(for: beaconRegion)
        let constraint = CLBeaconIdentityConstraint(uuid: targetUUID)
        locationManager.stopRangingBeacons(satisfying: constraint)
    }
    
    func confirmError() {
        self.showWifiAlert = false
        // 「今はエラーを知っている状態」にする
        self.isAlertSuppressed = true
        print("[UI] ユーザーがエラーを確認しました。次回成功するまでアラートを抑制します。")
    }
    
    private func startNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if path.status == .satisfied {
                    if path.usesInterfaceType(.wifi) {
                        // Wi-Fi接続中 -> サーバー確認
                        // ★ Wi-Fi自体はOKなので、ここではアラートを出さないが、
                        //   サーバー確認の結果次第でリセットするか決まるため、ここでは何もしない
                        self.checkServerReachability()
                    } else {
                        self.triggerAlert(message: "Wi-Fiに接続されていません。\n正しいローカルネットワークに接続してください。")
                    }
                } else {
                    self.triggerAlert(message: "ネットワーク接続がありません。\nWi-Fiを確認してください。")
                }
            }
        }
        networkMonitor?.start(queue: monitorQueue)
    }
    
    private func checkServerReachability() {
        guard let url = URL(string: ServerConfig.baseURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = ServerConfig.requestTimeoutInterval
        
        let task = ServerConfig.session.dataTask(with: request) { [weak self] _, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                // 1. エラー判定
                var isNowConnected = false
                
                if let httpResponse = response as? HTTPURLResponse,
                   (httpResponse.statusCode == 200 || httpResponse.statusCode == 404) {
                    isNowConnected = true
                }

                // 2. 状態に応じた処理
                if isNowConnected {
                    // --- 【成功時】 ---
                    
                    // ★ もし「前回まで切断されていた(false)」なら、今回「復帰した(true)」ので成功アラートを出す
                    if !self.wasConnected {
                        self.successMessage = "サーバーとの通信を確認しました。"
                        self.showSuccessAlert = true
                        print("[UI] 接続成功メッセージを表示")
                    }
                    
                    // 状態を更新
                    self.wasConnected = true
                    self.isServerConnected = true
                    
                    // エラー抑制を解除（次に切れたらまたエラーを出すため）
                    self.isAlertSuppressed = false
                    self.showWifiAlert = false // エラーが出ていたら消す
                    
                } else {
                    // --- 【失敗時】 ---
                    
                    self.wasConnected = false // 状態を「切断」にする
                    self.isServerConnected = false
                    
                    let msg: String
                    if let error = error {
                        msg = "サーバー到達不能: \(error.localizedDescription)"
                    } else {
                        msg = "サーバー接続エラー (Status Code Error)"
                    }

                    print("[Network] \(msg)")

                    // エラーアラートを表示（抑制中なら出ない）
                    self.triggerAlert(message: "サーバーが見つかりません。\n社内Wi-Fiに接続してください。")
                }
            }
        }
        task.resume()
    }
    
    private func triggerAlert(message: String) {
        // 「ユーザーがまだ確認していない（抑制されていない）」場合のみ表示する
        if !self.isAlertSuppressed {
            self.wifiAlertMessage = message
            self.showWifiAlert = true
        }
    }
    
    private func startMotionDetectionLoop() {
        motionTimer = Timer.scheduledTimer(withTimeInterval: motionInterval, repeats: true) { [weak self] _ in
            self?.motionDetectionStep()
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            logMessage = "位置情報の許可OK。レンジングを開始します..."
            positioningPhase = .scanning
            startBeaconRanging()
        } else {
            logMessage = "位置情報の許可がありません。"
        }
    }
    
    private func startBeaconRanging() {
        let constraint = CLBeaconIdentityConstraint(uuid: targetUUID)
        locationManager.startRangingBeacons(satisfying: constraint)
        // バックグラウンドでもリージョン進入/退出を検知するためモニタリングを開始
        locationManager.startMonitoring(for: beaconRegion)
        locationManager.requestState(for: beaconRegion)
    }

    // MARK: - バックグラウンドBLEリージョン監視

    /// リージョン状態の判定 (バックグラウンドからの復帰時にも呼ばれる)
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard region.identifier == beaconRegion.identifier else { return }
        if state == .inside {
            print("[BG] ビーコンリージョン内にいます。レンジングを開始します。")
            let constraint = CLBeaconIdentityConstraint(uuid: targetUUID)
            locationManager.startRangingBeacons(satisfying: constraint)
        } else if state == .outside {
            print("[BG] ビーコンリージョン外です。レンジングを停止します。")
            let constraint = CLBeaconIdentityConstraint(uuid: targetUUID)
            locationManager.stopRangingBeacons(satisfying: constraint)
        }
    }

    /// ビーコンリージョンに進入した時 (バックグラウンドでも発火)
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == beaconRegion.identifier else { return }
        print("[BG] ビーコンリージョンに進入しました。")
        let constraint = CLBeaconIdentityConstraint(uuid: targetUUID)
        locationManager.startRangingBeacons(satisfying: constraint)
    }

    /// ビーコンリージョンから退出した時 (バックグラウンドでも発火)
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == beaconRegion.identifier else { return }
        print("[BG] ビーコンリージョンから退出しました。")
        let constraint = CLBeaconIdentityConstraint(uuid: targetUUID)
        locationManager.stopRangingBeacons(satisfying: constraint)
    }

    /// リージョン監視失敗時のエラーハンドリング
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print("[BG] リージョン監視エラー: \(error.localizedDescription)")
    }

    // MARK: - バックグラウンドタスク管理

    /// バックグラウンドでサーバー通信を完了させるためのタスクを開始
    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "TohataBeaconTask") { [weak self] in
            self?.endBackgroundTask()
        }
        print("[BG] バックグラウンドタスク開始 (ID: \(backgroundTaskID))")
    }

    /// バックグラウンドタスクを終了
    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        print("[BG] バックグラウンドタスク終了 (ID: \(backgroundTaskID))")
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    // ---BLE観測ステップ (30秒ごと)---
    func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying constraint: CLBeaconIdentityConstraint) {
        
        var rawLogText = "--- 検出ビーコン (RAW) ---\n"
        var processingLogText = ""

        // 1. RAWログ (変更なし)
        if beacons.isEmpty {
            rawLogText += "ビーコンが見つかりません。\n"
        } else {
            for beacon in beacons {
                rawLogText += "Minor: \(beacon.minor.intValue), RSSI: \(beacon.rssi), Dist(Acc): \(String(format: "%.2f", beacon.accuracy))m\n"
            }
        }

        // 2. サンプリング処理 (変更なし)
        var detectedMinors: Set<Int> = []
        for beacon in beacons {
            let minor = beacon.minor.intValue
            guard beaconCoordinates[minor] != nil else { continue }
            detectedMinors.insert(minor)
            let distanceInMeters = beacon.accuracy
            if distanceInMeters <= 0 || distanceInMeters.isNaN || distanceInMeters > BeaconConfig.maxValidDistanceMeters { continue }
            let distanceInMillimeters = floor(distanceInMeters * 1000.0)
            if distanceInMillimeters <= 0 { continue }
            
            if beaconSampleBuffers[minor] == nil { beaconSampleBuffers[minor] = [] }
            beaconSampleBuffers[minor]?.append(distanceInMillimeters)
            
            processingLogText += "Minor: \(minor), Dist: \(String(format: "%.0f", distanceInMillimeters))mm (サンプル: \(beaconSampleBuffers[minor]?.count ?? 0)/\(currentSampleCount))\n"

            if let buffer = beaconSampleBuffers[minor], buffer.count >= currentSampleCount {
                let median = calculateMedian(from: buffer)
                medianDistances[minor] = median
                processingLogText += "--- ★ Minor \(minor) の中央値計算完了: \(String(format: "%.0f", median))mm ★ ---\n"
                beaconSampleBuffers[minor]?.removeAll()
            }
        }

        // アクティブビーコンを更新
        DispatchQueue.main.async {
            self.activeBeaconMinors = detectedMinors

            // ビーコン別サンプル進捗を更新
            var progress: [Int: (current: Int, required: Int)] = [:]
            for (minor, _) in self.beaconCoordinates {
                let current = self.beaconSampleBuffers[minor]?.count ?? 0
                let hasMedian = self.medianDistances[minor] != nil
                progress[minor] = (current: hasMedian ? self.currentSampleCount : current, required: self.currentSampleCount)
            }
            self.beaconSampleProgress = progress
            self.medianReadyCount = self.medianDistances.count

            if detectedMinors.isEmpty {
                self.positioningPhase = .scanning
            } else {
                self.positioningPhase = .collecting
            }
        }

        // 3. 測位リストを作成
        var beaconsForTrilateration: [(minor: Int, coordinates: (x: Double, y: Double), distance: Double)] = []
        for (minor, coords) in beaconCoordinates {
            if let medianDist = medianDistances[minor] {
                beaconsForTrilateration.append((minor: minor, coordinates: coords, distance: medianDist))
            } else {
                processingLogText += "Minor: \(minor) は中央値の計算待ちです。\n"
            }
        }

        // 4. 測位計算（移動中/静止中に関わらず常に実行）
        if beaconsForTrilateration.count == BeaconConfig.requiredBeaconCount {
            DispatchQueue.main.async { self.positioningPhase = .calculating }
            if useServerSideShapely {
                processingLogText += "--- 中央値をサーバー(Shapely)に送信し、計算をリクエスト... ---"
                requestShapelyPositionFromServer(beaconsForTrilateration)
                self.medianDistances.removeAll()
            } else {
                if let lsmPosition = calculateLeastSquaresPosition(beacons: beaconsForTrilateration) {
                    let pi_ids_used = beaconsForTrilateration.map { $0.minor }
                    submitPosition(x: lsmPosition.x, y: lsmPosition.y, pi_ids_used: pi_ids_used, calcMethod: "LSM")
                    sendRawDataToServer(beaconsForTrilateration)
                } else {
                    processingLogText += "--- 位置の計算に失敗しました (LSM) ---"
                }
                self.medianDistances.removeAll()
            }
        } else {
            processingLogText += "計算に必要な\(BeaconConfig.requiredBeaconCount)台の中央値が揃っていません。 (現在: \(beaconsForTrilateration.count)台)"
            DispatchQueue.main.async { self.positioningPhase = .insufficientBeacons }
        }
        
        self.logMessage = rawLogText + "\n--- 測位ステータス ---\n" + processingLogText
    }
    
    
    // --- 動静検知ステップ（加速度のみ） ---
    private func motionDetectionStep() {
        guard let motion = motionManager.deviceMotion else { return }
        let ax = motion.userAcceleration.x
        let ay = motion.userAcceleration.y
        let az = motion.userAcceleration.z
        let magnitude = sqrt(ax*ax + ay*ay + az*az)
        DispatchQueue.main.async {
            self.isUserMoving = magnitude > self.motionThreshold
        }
    }

    // --- BLE測位結果をサーバーに直接送信（KFなし） ---
    private func submitPosition(x: Double, y: Double, pi_ids_used: [Int], calcMethod: String) {
        let pos = (x: floor(x), y: floor(y))
        print("[BLE] 測位結果: (\(pos.x), \(pos.y)) method=\(calcMethod)")
        self.sendPositionToServer(
            position: pos,
            pi_ids_used: pi_ids_used,
            calcMethod: calcMethod
        )
    }

    // --- LSM計算関数 ---
    private func calculateLeastSquaresPosition(beacons: [(minor: Int, coordinates: (x: Double, y: Double), distance: Double)]) -> (x: Double, y: Double)? {
        guard beacons.count == BeaconConfig.requiredBeaconCount else { return nil }
        let numEquations = beacons.count - 1
        var matrixA = [Double](repeating: 0.0, count: numEquations * 2)
        var vectorB = [Double](repeating: 0.0, count: numEquations)
        let x0 = beacons[0].coordinates.x
        let y0 = beacons[0].coordinates.y
        let d0_sq = beacons[0].distance * beacons[0].distance
        let k0 = x0*x0 + y0*y0
        for i in 0..<numEquations {
            let beacon_i = beacons[i + 1]
            let xi = beacon_i.coordinates.x
            let yi = beacon_i.coordinates.y
            let di_sq = beacon_i.distance * beacon_i.distance
            let ki = xi*xi + yi*yi
            matrixA[i*2 + 0] = 2.0 * (x0 - xi)
            matrixA[i*2 + 1] = 2.0 * (y0 - yi)
            vectorB[i] = (di_sq - d0_sq) - (ki - k0)
        }
        var n = Int32(numEquations)
        var m = Int32(2)
        var nrhs = Int32(1)
        var info: Int32 = 0
        var lwork = Int32(max(1, Int(m + n))) * 2
        var work = [Double](repeating: 0.0, count: Int(lwork))
        var A_copy = matrixA
        var b_copy = vectorB
        var trans: CChar = 78
        var lda = n
        var ldb = n
        dgels_(&trans, &n, &m, &nrhs, &A_copy, &lda, &b_copy, &ldb, &work, &lwork, &info)
        if info == 0 {
            return (x: b_copy[0], y: b_copy[1])
        } else {
            return nil
        }
    }
    
    // --- Shapelyフォールバック用 ---
    private func calculateTrilateration(beacon1: (coordinates: (x: Double, y: Double), distance: Double),
                                        beacon2: (coordinates: (x: Double, y: Double), distance: Double),
                                        beacon3: (coordinates: (x: Double, y: Double), distance: Double)) -> (x: Double, y: Double)? {
        let (x1, y1) = beacon1.coordinates
        let d1 = beacon1.distance
        let (x2, y2) = beacon2.coordinates
        let d2 = beacon2.distance
        let (x3, y3) = beacon3.coordinates
        let d3 = beacon3.distance
        let A = 2.0 * (x2 - x1)
        let B = 2.0 * (y2 - y1)
        let C = (d1*d1 - d2*d2) - (x1*x1 - x2*x2) - (y1*y1 - y2*y2)
        let D = 2.0 * (x3 - x2)
        let E = 2.0 * (y3 - y2)
        let F = (d2*d2 - d3*d3) - (x2*x2 - x3*x3) - (y2*y2 - y3*y3)
        let denominator = (A * E) - (D * B)
        if abs(denominator) < 1e-6 { return nil }
        let x = ((C * E) - (F * B)) / denominator
        let y = ((A * F) - (D * C)) / denominator
        return (x: x, y: y)
    }

    private func fallbackToTrilateration(rawData: [(minor: Int, coordinates: (x: Double, y: Double), distance: Double)]) {
        DispatchQueue.main.async {
            print("[Fallback] Shapely計算に失敗。iPhone(3点測位)で計算します。")
            guard rawData.count == BeaconConfig.requiredBeaconCount else { return }
            let sortedBeacons = rawData.sorted { $0.distance < $1.distance }
            let beaconsToUse = Array(sortedBeacons.prefix(3))
            if let trilatPosition = self.calculateTrilateration(
                beacon1: (coordinates: beaconsToUse[0].coordinates, distance: beaconsToUse[0].distance),
                beacon2: (coordinates: beaconsToUse[1].coordinates, distance: beaconsToUse[1].distance),
                beacon3: (coordinates: beaconsToUse[2].coordinates, distance: beaconsToUse[2].distance)
            ) {
                let pi_ids_used = beaconsToUse.map { $0.minor }
                self.submitPosition(x: trilatPosition.x, y: trilatPosition.y, pi_ids_used: pi_ids_used, calcMethod: "TRILAT_FALLBACK")
            }
        }
    }
    
    // --- 中央値計算 ---
    private func calculateMedian(from samples: [Double]) -> Double {
        if samples.isEmpty { return 0.0 }
        let sortedSamples = samples.sorted()
        let count = sortedSamples.count
        if count % 2 == 0 {
            return floor((sortedSamples[(count / 2) - 1] + sortedSamples[count / 2]) / 2.0)
        } else {
            return sortedSamples[count / 2]
        }
    }
    
    // --- API送信 (ポート5001) ---
    private func sendPositionToServer(position: (x: Double, y: Double), pi_ids_used: [Int], calcMethod: String) {
        guard let url = ServerConfig.url(for: ServerConfig.Endpoint.addLocation) else { return }
        beginBackgroundTask()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "beacon_id": self.deviceID,
            "user_name": self.currentUserName,
            "job_title": self.currentJobTitle,
            "department": self.currentDepartment,
            "status": self.currentStatus,
            "lsm_x": position.x, "lsm_y": position.y,
            "kf_x": position.x, "kf_y": position.y,
            "pi_ids_used": pi_ids_used,
            "snap_enabled": self.isSnappingEnabled,
            "detailed_logging": self.isDetailedLoggingEnabled,
            "calc_method": calcMethod,
            "is_moving": self.isUserMoving
        ]
        do { request.httpBody = try JSONSerialization.data(withJSONObject: body, options: []) } catch {
            endBackgroundTask(); return
        }

        let task = ServerConfig.session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            defer { self.endBackgroundTask() }
            if error != nil {
                print("[DB] 送信エラー: サーバーが見つかりません")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 else {
                print("[DB] 失敗 (Status: \((response as? HTTPURLResponse)?.statusCode ?? 0))")
                return
            }
            guard let data = data else { return }

            do {
                if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let status = jsonResponse["status"] as? String, status == "success",
                   let snappedX = jsonResponse["snapped_x"] as? Double,
                   let snappedY = jsonResponse["snapped_y"] as? Double {
                    DispatchQueue.main.async {
                        self.estimatedPosition = (x: floor(snappedX), y: floor(snappedY))
                        self.positioningPhase = .positioned
                        self.lastPositionedAt = Date()
                        self.showWifiAlert = false
                        print("[DB] UI更新: (\(snappedX), \(snappedY))")
                        // ニアバイ通知チェック (60秒に1回)
                        self.checkNearbyMatchesIfNeeded()
                    }
                }
            } catch { print("[DB] JSON解析失敗") }
        }
        task.resume()
    }
    
    private func sendRawDataToServer(_ rawData: [(minor: Int, coordinates: (x: Double, y: Double), distance: Double)]) {
        guard let url = ServerConfig.url(for: ServerConfig.Endpoint.addRawDataBatch) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let rawDataList = rawData.map { ["ras_pi_id": $0.minor, "distance": $0.distance] }
        let body: [String: Any] = ["beacon_id": self.deviceID, "raw_data": rawDataList]
        do { request.httpBody = try JSONSerialization.data(withJSONObject: body, options: []) } catch { return }
        let task = ServerConfig.session.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 {
                print("[DB-RAW] 成功 (201)")
            }
        }
        task.resume()
    }

    private func requestShapelyPositionFromServer(_ rawData: [(minor: Int, coordinates: (x: Double, y: Double), distance: Double)]) {
        guard let url = ServerConfig.url(for: ServerConfig.Endpoint.calculateFromIPhone) else { return }
        beginBackgroundTask()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let rawDataList = rawData.map { ["ras_pi_id": $0.minor, "distance": $0.distance] }
        let body: [String: Any] = ["beacon_id": self.deviceID, "raw_data": rawDataList]

        do { request.httpBody = try JSONSerialization.data(withJSONObject: body, options: []) } catch {
            endBackgroundTask(); return
        }

        let task = ServerConfig.session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            defer { self.endBackgroundTask() }

            // エラーハンドリング
            if error != nil {
                self.fallbackToTrilateration(rawData: rawData)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                self.fallbackToTrilateration(rawData: rawData); return
            }
            guard let data = data else { self.fallbackToTrilateration(rawData: rawData); return }

            do {
                if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let status = jsonResponse["status"] as? String, status == "success",
                   let obs_x = jsonResponse["x"] as? Double,
                   let obs_y = jsonResponse["y"] as? Double,
                   let pi_ids_used = jsonResponse["pi_ids_used"] as? [Int] {

                    DispatchQueue.main.async {
                        self.showWifiAlert = false
                        // BLE測位結果を直接送信（KFなし）
                        self.submitPosition(x: obs_x, y: obs_y, pi_ids_used: pi_ids_used, calcMethod: "SHAPELY")
                    }
                } else {
                    self.fallbackToTrilateration(rawData: rawData)
                }
            } catch {
                self.fallbackToTrilateration(rawData: rawData)
            }
        }
        task.resume()
    }

    // MARK: - プロフィール送信

    /// ユーザープロフィール情報をサーバーに送信する
    func sendProfileToServer(skills: String, hobbies: String, projects: String, email: String, phone: String,
                             completion: @escaping (Bool) -> Void) {
        guard let url = ServerConfig.url(for: ServerConfig.Endpoint.updateUserProfile) else {
            completion(false); return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = ServerConfig.requestTimeoutInterval

        let body: [String: Any] = [
            "beacon_id": self.deviceID,
            "user_name": self.currentUserName,
            "job_title": self.currentJobTitle,
            "department": self.currentDepartment,
            "skills": skills,
            "hobbies": hobbies,
            "projects": projects,
            "email": email,
            "phone": phone
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            completion(false); return
        }

        let task = ServerConfig.session.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                completion(true)
            } else {
                completion(false)
            }
        }
        task.resume()
    }

    /// プロフィール画像をサーバーにアップロードする
    func uploadProfileImage(imageData: Data, completion: @escaping (Bool, String?) -> Void) {
        guard let url = ServerConfig.url(for: ServerConfig.Endpoint.uploadProfileImage) else {
            completion(false, nil); return
        }
        let boundary = UUID().uuidString

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        var body = Data()
        // beacon_id フィールド
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"beacon_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(self.deviceID)\r\n".data(using: .utf8)!)
        // image フィールド
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"profile.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let task = ServerConfig.session.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                completion(false, nil); return
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let imageUrl = json["image_url"] as? String {
                completion(true, imageUrl)
            } else {
                completion(false, nil)
            }
        }
        task.resume()
    }

    // MARK: - ニアバイ通知 (Feature 2)
    private var lastNearbyCheckTime: Date = .distantPast
    private var lastNotifiedBeaconIds: Set<String> = []

    func checkNearbyMatchesIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastNearbyCheckTime) > 60 else { return }
        lastNearbyCheckTime = now

        guard let url = URL(string: "\(ServerConfig.baseURL)/api/nearby_matches?beacon_id=\(self.deviceID)&radius_mm=3000") else { return }

        ServerConfig.session.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, error == nil, let data = data else { return }
            guard let response = try? JSONDecoder().decode(NearbyMatchResponse.self, from: data) else { return }

            let newIds = Set(response.matches.map { $0.beacon_id })
            let brandNew = newIds.subtracting(self.lastNotifiedBeaconIds)

            if !brandNew.isEmpty {
                let newMatches = response.matches.filter { brandNew.contains($0.beacon_id) }
                self.scheduleNearbyNotification(matches: newMatches)
            }
            self.lastNotifiedBeaconIds = newIds
        }.resume()
    }

    private func scheduleNearbyNotification(matches: [NearbyMatch]) {
        let content = UNMutableNotificationContent()
        content.title = "近くにマッチする人がいます"
        let names = matches.prefix(3).compactMap { $0.user_name }.joined(separator: ", ")
        let fields = matches.flatMap { $0.matching_fields }.prefix(3).joined(separator: ", ")
        content.body = names.isEmpty ? "マッチする人が近くにいます" : "\(names) — \(fields)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "nearby_match_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }
}

