//
//  AppConfig.swift
//  tohata_ios_02
//
//  定数・設定値の一元管理ファイル
//

import Foundation
import SwiftUI

// MARK: - サーバー設定
enum ServerConfig {
    static let ngrokURL = "https://your-server.ngrok-free.dev"

    /// LAN接続のデフォルトポート
    static let defaultPort = 5000

    /// 現在の接続先URL（ユーザーが管理画面で切り替え可能）
    static var baseURL: String {
        let saved = UserDefaults.standard.string(forKey: "serverBaseURL") ?? ""
        return saved.isEmpty ? ngrokURL : saved
    }

    /// 接続先URLを保存
    static func setBaseURL(_ url: String) {
        UserDefaults.standard.set(url, forKey: "serverBaseURL")
    }

    /// ngrokにリセット
    static func resetToNgrok() {
        UserDefaults.standard.removeObject(forKey: "serverBaseURL")
    }

    /// ngrok経由で接続中か
    static var isNgrok: Bool {
        return baseURL.contains("ngrok")
    }

    /// LAN直接接続中か
    static var isLAN: Bool {
        let url = baseURL
        return url.contains("192.168.") || url.contains("10.") || url.contains("172.") || url.hasPrefix("http://localhost")
    }

    /// 接続モードの表示名
    static var connectionMode: String {
        if isLAN { return "LAN" }
        if isNgrok { return "ngrok" }
        return "カスタム"
    }

    static let requestTimeoutInterval: TimeInterval = 3.0

    /// ngrok ブラウザ警告をスキップするヘッダー付き URLSession（画像キャッシュ対応）
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "ngrok-skip-browser-warning": "true",
            "User-Agent": "TohataApp/1.0"
        ]
        config.timeoutIntervalForRequest = requestTimeoutInterval
        // URLキャッシュ: 50MB メモリ / 200MB ディスク
        config.urlCache = URLCache(memoryCapacity: 50 * 1024 * 1024,
                                   diskCapacity: 200 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    /// キャッシュ無視で最新データを取得する用（APIデータ取得向け）
    static let liveSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "ngrok-skip-browser-warning": "true",
            "User-Agent": "TohataApp/1.0"
        ]
        config.timeoutIntervalForRequest = requestTimeoutInterval
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    // APIエンドポイント
    enum Endpoint {
        static let addLocation       = "/api/add_location"
        static let addRawDataBatch   = "/api/add_raw_data_batch"
        static let calculateFromIPhone = "/api/calculate_from_iphone"
        static let updateUserProfile = "/api/update_user_profile"
        static let uploadProfileImage = "/api/upload_profile_image"
    }

    /// ダッシュボードのURL
    static var dashboardURL: URL? {
        return URL(string: baseURL)
    }

    /// 完全なエンドポイントURLを生成する
    static func url(for endpoint: String) -> URL? {
        return URL(string: baseURL + endpoint)
    }

    // MARK: - LAN自動検出

    /// 同一WiFi上のサーバーを自動検出（指定ポートにGETリクエスト）
    static func detectLANServer(port: Int = defaultPort, timeout: TimeInterval = 1.5) async -> String? {
        guard let localIP = getWiFiAddress() else {
            print("[LAN] WiFiアドレスを取得できません")
            return nil
        }
        let prefix = localIP.components(separatedBy: ".").prefix(3).joined(separator: ".")
        print("[LAN] ネットワークスキャン開始: \(prefix).x:\(port)")

        // よく使われるアドレスから優先的にチェック
        let priorityHosts = [localIP] + (1...254).map { "\(prefix).\($0)" }.filter { $0 != localIP }

        return await withTaskGroup(of: String?.self) { group in
            for host in priorityHosts.prefix(30) {  // 最初の30台のみスキャン
                group.addTask {
                    let urlStr = "http://\(host):\(port)/api/app_config"
                    guard let url = URL(string: urlStr) else { return nil }
                    var request = URLRequest(url: url)
                    request.timeoutInterval = timeout
                    request.cachePolicy = .reloadIgnoringLocalCacheData
                    do {
                        let (_, response) = try await URLSession.shared.data(for: request)
                        if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                            print("[LAN] サーバー発見: \(host):\(port)")
                            return "http://\(host):\(port)"
                        }
                    } catch { }
                    return nil
                }
            }
            for await result in group {
                if let found = result {
                    group.cancelAll()
                    return found
                }
            }
            return nil
        }
    }

    /// デバイスのWiFi IPアドレスを取得
    private static func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            guard addrFamily == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
            address = String(cString: hostname)
        }
        return address
    }
}

// MARK: - ビーコン設定
enum BeaconConfig {
    /// ビーコンのUUID
    static let targetUUID = UUID(uuidString: "DD05B849-BB42-4AB8-B8F3-798B42440C4E")!
    
    /// ビーコンの座標 (mm単位, Y軸は負) - 9台グリッド配置
    /// ※ サーバーのBEACON_POSITIONS / PI_LOCATIONSと同じ負Y座標系
    static let coordinates: [Int: (x: Double, y: Double)] = [
        1: (x: 1284, y: -2100),    // ras_01
        2: (x: 3444, y: -2132),    // ras_02
        3: (x: 1288, y: -4806),    // ras_03
        4: (x: 3419, y: -4806),    // ras_04
        5: (x: 6660, y: -2132),    // ras_05
        6: (x: 6660, y: -4818),    // ras_06
        7: (x: 1288, y: -7845),    // ras_07
        8: (x: 3381, y: -7807),    // ras_08
        9: (x: 6660, y: -7845),    // ras_09
    ]
    
    /// 測位に必要なビーコン台数
    static let requiredBeaconCount = 9
    
    /// 距離のサンプリング回数 (フォアグラウンド)
    static let sampleCount = 30

    /// バックグラウンド時のサンプリング回数 (実行時間が限られるため少なく)
    static let backgroundSampleCount = 5
    
    /// 有効な最大距離 (m)
    static let maxValidDistanceMeters = 50.0
}

// MARK: - センサー / カルマンフィルター設定
enum SensorConfig {
    /// KF予測ループの更新間隔 (秒) = 50Hz
    static let kfInterval: TimeInterval = 0.02
    
    /// 動き判定の閾値 (G)
    static let motionThreshold: Double = 0.1
    
    /// KF補正の観測値反映比率 (0.0〜1.0)
    static let kfObservationWeight: Double = 0.7
    
    /// 重力加速度 → mm/s² への変換係数
    static let gravityToMillimetersPerSecSquared: Double = 9800.0
}

// MARK: - ユーザーデフォルト設定
enum UserDefaultsConfig {
    static let defaultUserName   = "ゲスト"
    static let defaultJobTitle   = "unknown"
    static let defaultDepartment = "other"
    static let defaultStatus     = "available"
    
    // AppStorage キー
    enum Keys {
        static let userName = "userName"
        static let userJob  = "userJob"
        static let userDept = "userDept"
        static let userSkills  = "userSkills"
        static let userHobbies = "userHobbies"
        static let userProjects = "userProjects"
        static let userEmail   = "userEmail"
        static let userPhone   = "userPhone"
    }
}

// MARK: - 選択肢オプション
enum PickerOptions {
    /// 役職 (value, displayLabel)
    static let jobOptions: [(String, String)] = [
        ("unknown",  "未設定"),
        ("engineer", "エンジニア"),
        ("manager",  "マネージャー"),
        ("sales",    "営業"),
        ("admin",    "事務")
    ]
    
    /// 部署 (value, displayLabel)
    static let deptOptions: [(String, String)] = [
        ("other",      "その他"),
        ("dev_team",   "開発部"),
        ("sales_team", "営業部"),
        ("hr_team",    "総務部")
    ]
    
    /// ステータス (value, displayLabel)
    static let statusOptions: [(String, String)] = [
        ("available", "✅ 取込可"),
        ("busy",      "⛔️ 取込中"),
        ("meeting",   "🗣️ 会議中"),
        ("break",     "☕️ 休憩中")
    ]
}

// MARK: - 画像キャッシュ（NSCache + ディスク）
final class ImageCacheManager {
    static let shared = ImageCacheManager()
    private let memoryCache = NSCache<NSString, UIImage>()

    private init() {
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 50 * 1024 * 1024  // 50MB
    }

    func image(for url: URL) -> UIImage? {
        return memoryCache.object(forKey: url.absoluteString as NSString)
    }

    func store(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * image.scale * 4)
        memoryCache.setObject(image, forKey: url.absoluteString as NSString, cost: cost)
    }

    /// 非同期で画像を取得（キャッシュ優先）
    func loadImage(from url: URL) async -> UIImage? {
        if let cached = image(for: url) { return cached }
        do {
            // URLSessionのキャッシュも活用（session は returnCacheDataElseLoad）
            let (data, _) = try await ServerConfig.session.data(from: url)
            guard let img = UIImage(data: data) else { return nil }
            store(img, for: url)
            return img
        } catch {
            return nil
        }
    }
}

// MARK: - CachedAsyncImage（AsyncImage のキャッシュ対応版）
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var uiImage: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
                    .onAppear { load() }
            }
        }
    }

    private func load() {
        guard let url, !isLoading else { return }
        // メモリキャッシュの即時チェック
        if let cached = ImageCacheManager.shared.image(for: url) {
            uiImage = cached
            return
        }
        isLoading = true
        Task {
            let img = await ImageCacheManager.shared.loadImage(from: url)
            await MainActor.run {
                uiImage = img
                isLoading = false
            }
        }
    }
}
