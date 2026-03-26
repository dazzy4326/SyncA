//
//  APIService.swift
//  tohata_ios_02
//
//  サーバーAPIとの通信を管理するサービス
//

import Foundation
import Combine

@MainActor
class APIService: ObservableObject {
    // MARK: - Published プロパティ
    @Published var sensorData: [SensorReading] = []
    @Published var persons: [PersonPosition] = []
    @Published var profiles: [UserProfile] = []
    @Published var searchResults: [UserProfile] = []
    @Published var recommendation: RecommendationResponse?
    @Published var appConfig: AppConfig?
    @Published var lineChartData: [[ChartPoint]] = []
    @Published var skillSearchResults: [SkillSearchResult] = []
    @Published var nearbyMatches: [NearbyMatch] = []
    @Published var collabPosts: [CollabPost] = []
    @Published var interactionStats: InteractionStats?
    @Published var myInteractions: MyInteractions?
    @Published var todaysLunchMatch: LunchMatch?
    @Published var socialRecommendation: SocialRecommendation?
    @Published var userAvailability: UserAvailability?
    @Published var isLoading = false

    private var refreshTimer: Timer?
    private let maxChartPoints = 20

    /// DateFormatter はコストが高いため、インスタンスを再利用する
    private let chartTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // MARK: - 自動更新

    func startAutoRefresh(interval: TimeInterval = 10.0) {
        // タイマー重複防止: 既にタイマーが動いていたら再作成しない
        if refreshTimer != nil { return }
        refreshData()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshData()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refreshData() {
        Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.fetchSensorData() }
                group.addTask { await self.fetchPersonPositions() }
            }
        }
    }

    // MARK: - API 呼び出し

    /// configをサーバーから再取得する（fire-and-forget版）
    func fetchConfig() {
        Task { await fetchConfigAsync() }
    }

    /// configをサーバーから再取得する（await可能版）
    @MainActor
    func fetchConfigAsync() async {
        guard let url = URL(string: ServerConfig.baseURL + "/api/app_config") else { return }
        do {
            let (data, _) = try await ServerConfig.liveSession.data(from: url)
            let decoder = JSONDecoder()
            let config = try decoder.decode(AppConfig.self, from: data)
            self.appConfig = config
            print("[API] config取得成功: PI=\(config.PI_LOCATIONS?.count ?? 0)台, BEACON_POS=\(config.BEACON_POSITIONS?.count ?? 0)件, BOUNDARY=\(config.FLOOR_BOUNDARY?.count ?? 0)点")
        } catch {
            print("[API] config取得エラー: \(error)")
        }
    }

    func fetchSensorData() async {
        guard let url = URL(string: ServerConfig.baseURL + "/api/sensor-data") else { return }
        do {
            let (data, _) = try await ServerConfig.liveSession.data(from: url)
            let readings = try JSONDecoder().decode([SensorReading].self, from: data)
            self.sensorData = readings
            appendChartData(readings)
        } catch {
            print("[API] sensor-data取得エラー: \(error)")
        }
    }

    func fetchPersonPositions() async {
        guard let url = URL(string: ServerConfig.baseURL + "/api/get_iphone_positions") else { return }
        do {
            let (data, response) = try await ServerConfig.liveSession.data(from: url)
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode != 200 {
                print("[API] positions HTTPエラー: \(httpResp.statusCode)")
                return
            }
            let positions = try JSONDecoder().decode([PersonPosition].self, from: data)
            self.persons = positions
            if !positions.isEmpty {
                print("[API] positions取得成功: \(positions.count)人")
            }
        } catch {
            print("[API] positions取得エラー: \(error)")
        }
    }

    func fetchAllProfiles() async {
        guard let url = URL(string: ServerConfig.baseURL + "/api/user_profiles") else { return }
        do {
            let (data, _) = try await ServerConfig.liveSession.data(from: url)
            self.profiles = try JSONDecoder().decode([UserProfile].self, from: data)
        } catch {
            print("[API] profiles取得エラー: \(error)")
        }
    }

    func searchUsers(query: String, department: String?, jobTitle: String?, sort: String) async {
        var components = URLComponents(string: ServerConfig.baseURL + "/api/search_users")!
        var items: [URLQueryItem] = []
        if !query.isEmpty { items.append(.init(name: "q", value: query)) }
        if let d = department, !d.isEmpty { items.append(.init(name: "department", value: d)) }
        if let j = jobTitle, !j.isEmpty { items.append(.init(name: "job_title", value: j)) }
        items.append(.init(name: "sort", value: sort))
        components.queryItems = items

        guard let url = components.url else { return }
        do {
            let (data, _) = try await ServerConfig.liveSession.data(from: url)
            self.searchResults = try JSONDecoder().decode([UserProfile].self, from: data)
        } catch {
            print("[API] search取得エラー: \(error)")
        }
    }

    func fetchRecommendations(temp: String, occupancy: String, light: String, humidity: String = "any", co2: String = "any") async {
        var components = URLComponents(string: ServerConfig.baseURL + "/api/recommendations")!
        components.queryItems = [
            .init(name: "temp", value: temp),
            .init(name: "occupancy", value: occupancy),
            .init(name: "light", value: light),
            .init(name: "humidity", value: humidity),
            .init(name: "co2", value: co2)
        ]
        guard let url = components.url else { return }
        do {
            let (data, _) = try await ServerConfig.liveSession.data(from: url)
            self.recommendation = try JSONDecoder().decode(RecommendationResponse.self, from: data)
        } catch {
            print("[API] recommendations取得エラー: \(error)")
        }
    }

    // MARK: - チャートデータ蓄積

    private func appendChartData(_ readings: [SensorReading]) {
        let now = Date()
        let timeLabel = chartTimeFormatter.string(from: now)

        // 折れ線: Pi ごとにデータポイントを追加
        if lineChartData.isEmpty {
            lineChartData = readings.map { _ in [] }
        }
        for (index, reading) in readings.enumerated() {
            guard index < lineChartData.count else { break }
            let point = ChartPoint(
                time: timeLabel,
                piName: reading.id,
                temp: reading.value(for: .temp),
                humidity: reading.value(for: .humidity),
                lux: reading.value(for: .lux),
                co2: reading.value(for: .co2)
            )
            lineChartData[index].append(point)
            if lineChartData[index].count > maxChartPoints {
                lineChartData[index].removeFirst()
            }
        }
    }

    // MARK: - 管理者API

    func verifyAdminPassword(_ password: String) async -> Bool {
        guard let url = URL(string: ServerConfig.baseURL + "/api/verify_admin_password") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["password": password])
        do {
            let (data, response) = try await ServerConfig.liveSession.data(for: request)
            // サーバーは成功時 200 + {"status":"success"}、失敗時 401 を返す
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String {
                    return status == "success"
                }
                return true
            }
            return false
        } catch {
            print("[API] 認証エラー: \(error)")
            return false
        }
    }

    func uploadFloorplan(imageData: Data, filename: String) async -> Bool {
        guard let url = URL(string: ServerConfig.baseURL + "/api/upload_floorplan") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        do {
            let (_, response) = try await ServerConfig.liveSession.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { await fetchConfigAsync() }
            return status == 200
        } catch {
            print("[API] floorplanアップロードエラー: \(error)")
            return false
        }
    }

    func updateUserProfile(_ profile: UserProfile) async -> Bool {
        guard let url = URL(string: ServerConfig.baseURL + "/api/update_user_profile") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(profile)
        do {
            let (_, response) = try await ServerConfig.liveSession.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            print("[API] profile更新エラー: \(error)")
            return false
        }
    }

    func uploadProfileImage(beaconId: String, imageData: Data) async -> String? {
        guard let url = URL(string: ServerConfig.baseURL + "/api/upload_profile_image") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"beacon_id\"\r\n\r\n\(beaconId)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"profile.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        do {
            let (data, response) = try await ServerConfig.liveSession.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json["image_url"] as? String
            }
            return nil
        } catch {
            print("[API] 画像アップロードエラー: \(error)")
            return nil
        }
    }

    // MARK: - キャリブレーション更新

    func updateCalibration(originX: Double, originY: Double, scale: Double) async -> Bool {
        guard let url = URL(string: ServerConfig.baseURL + "/api/update_calibration") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "origin_px": ["x": originX, "y": originY],
            "scale_mm_per_px": scale
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await ServerConfig.liveSession.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { await fetchConfigAsync() }
            return status == 200
        } catch {
            print("[API] キャリブレーション更新エラー: \(error)")
            return false
        }
    }

    // MARK: - ビーコン設定更新 (ビーコン配置 + 椅子 + 廊下)

    func updateBeaconConfig(
        positions: [String: [Double]],
        minorIdMap: [String: String],
        chairCenters: [[Double]],
        centerLines: [[String: Any]]
    ) async -> Bool {
        guard let url = URL(string: ServerConfig.baseURL + "/api/update_beacon_config") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "BEACON_POSITIONS": positions,
            "MINOR_ID_TO_PI_NAME_MAP": minorIdMap,
            "CHAIR_CENTERS": chairCenters,
            "CENTER_LINES": centerLines
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await ServerConfig.liveSession.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { await fetchConfigAsync() }
            return status == 200
        } catch {
            print("[API] ビーコン設定更新エラー: \(error)")
            return false
        }
    }

    // MARK: - フロア外枠更新

    func updateFloorBoundary(boundary: [[String: Double]]) async -> Bool {
        guard let url = URL(string: ServerConfig.baseURL + "/api/update_floor_boundary") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["FLOOR_BOUNDARY": boundary]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await ServerConfig.liveSession.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { await fetchConfigAsync() }
            return status == 200
        } catch {
            print("[API] フロア外枠更新エラー: \(error)")
            return false
        }
    }

    // MARK: - フロアオブジェクト更新

    func updateFloorObjects(objects: [[String: Any]]) async -> (Bool, String) {
        guard let url = URL(string: ServerConfig.baseURL + "/api/update_floor_objects") else {
            return (false, "URL無効")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15  // 書き込み処理のため長めに設定
        let body: [String: Any] = ["FLOOR_OBJECTS": objects]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        print("[API] フロアオブジェクト送信: \(objects.count)件 → \(url)")
        do {
            let (data, response) = try await ServerConfig.liveSession.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let responseStr = String(data: data, encoding: .utf8) ?? "(no body)"
            print("[API] フロアオブジェクト応答: status=\(status), body=\(responseStr)")
            if status == 200 {
                await fetchConfigAsync()
                return (true, "保存成功")
            }
            // サーバーからのエラーメッセージを取得
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = json["message"] as? String {
                return (false, "サーバーエラー(\(status)): \(msg)")
            }
            return (false, "サーバーエラー: HTTP \(status)")
        } catch let error as URLError {
            print("[API] フロアオブジェクト更新エラー: \(error)")
            switch error.code {
            case .timedOut:
                return (false, "タイムアウト: サーバーに接続できません")
            case .cannotConnectToHost, .cannotFindHost:
                return (false, "接続エラー: サーバーが見つかりません")
            case .notConnectedToInternet:
                return (false, "ネットワーク未接続")
            default:
                return (false, "通信エラー: \(error.localizedDescription)")
            }
        } catch {
            print("[API] フロアオブジェクト更新エラー: \(error)")
            return (false, "エラー: \(error.localizedDescription)")
        }
    }

    // MARK: - ユーザープロフィール削除

    func deleteUserProfile(beaconId: String) async -> Bool {
        guard let url = URL(string: ServerConfig.baseURL + "/api/delete_user_profile/\(beaconId)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        do {
            let (_, response) = try await ServerConfig.liveSession.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            print("[API] ユーザー削除エラー: \(error)")
            return false
        }
    }

    // MARK: - ヘルパー

    func average(for sensor: SensorType) -> Double {
        let values = sensorData.compactMap { $0.value(for: sensor) }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    func floorplanURL() -> URL? {
        guard let path = appConfig?.FLOORPLAN_IMAGE?.url, !path.isEmpty else { return nil }
        return URL(string: ServerConfig.baseURL + path)
    }

    // MARK: - ソーシャル機能API

    func searchBySkill(skill: String) async {
        var components = URLComponents(string: ServerConfig.baseURL + "/api/skill_search")!
        components.queryItems = [
            .init(name: "skill", value: skill)
        ]
        guard let url = components.url else { return }
        do {
            let (data, _) = try await ServerConfig.liveSession.data(from: url)
            self.skillSearchResults = try JSONDecoder().decode([SkillSearchResult].self, from: data)
        } catch {
            print("[API] skill_search取得エラー: \(error)")
        }
    }

    func fetchNearbyMatches(beaconId: String, radiusMm: Int = 3000) async {
        var components = URLComponents(string: ServerConfig.baseURL + "/api/nearby_matches")!
        components.queryItems = [
            .init(name: "beacon_id", value: beaconId),
            .init(name: "radius_mm", value: String(radiusMm))
        ]
        guard let url = components.url else { return }
        do {
            let (data, _) = try await ServerConfig.liveSession.data(from: url)
            let response = try JSONDecoder().decode(NearbyMatchResponse.self, from: data)
            self.nearbyMatches = response.matches
        } catch {
            print("[API] nearby_matches取得エラー: \(error)")
        }
    }

    func fetchUserAvailability(beaconId: String) async {
        guard let url = URL(string: ServerConfig.baseURL + "/api/user_availability/\(beaconId)") else { return }
        do {
            let (data, _) = try await ServerConfig.liveSession.data(from: url)
            self.userAvailability = try JSONDecoder().decode(UserAvailability.self, from: data)
        } catch {
            print("[API] user_availability取得エラー: \(error)")
        }
    }

    func updateUserAvailability(_ availability: UserAvailability) async -> Bool {
        guard let url = URL(string: ServerConfig.baseURL + "/api/update_user_availability") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(availability)
        do {
            let (_, response) = try await ServerConfig.liveSession.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            print("[API] update_user_availability更新エラー: \(error)")
            return false
        }
    }

    func fetchCollabPosts(status: String = "open", skill: String? = nil, hours: Int? = nil, postType: String? = nil) async {
        var components = URLComponents(string: ServerConfig.baseURL + "/api/collab_posts")!
        var items: [URLQueryItem] = [
            .init(name: "status", value: status)
        ]
        if let s = skill, !s.isEmpty {
            items.append(.init(name: "skill", value: s))
        }
        if let h = hours {
            items.append(.init(name: "hours", value: String(h)))
        }
        if let pt = postType, !pt.isEmpty {
            items.append(.init(name: "post_type", value: pt))
        }
        components.queryItems = items
        guard let url = components.url else { return }
        do {
            let (data, _) = try await ServerConfig.liveSession.data(from: url)
            self.collabPosts = try JSONDecoder().decode([CollabPost].self, from: data)
        } catch {
            print("[API] collab_posts取得エラー: \(error)")
        }
    }

    func createCollabPost(beaconId: String, userName: String, postType: String, title: String, description: String, requiredSkills: String) async -> Bool {
        guard let url = URL(string: ServerConfig.baseURL + "/api/collab_posts") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "beacon_id": beaconId,
            "user_name": userName,
            "post_type": postType,
            "title": title,
            "description": description,
            "required_skills": requiredSkills
        ]
        request.httpBody = try? JSONEncoder().encode(body)
        do {
            let (_, response) = try await ServerConfig.liveSession.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            print("[API] collab_post作成エラー: \(error)")
            return false
        }
    }

    func respondToCollabPost(postId: Int, beaconId: String, userName: String, message: String) async -> Bool {
        guard let url = URL(string: ServerConfig.baseURL + "/api/collab_posts/\(postId)/respond") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "beacon_id": beaconId,
            "user_name": userName,
            "message": message
        ]
        request.httpBody = try? JSONEncoder().encode(body)
        do {
            let (_, response) = try await ServerConfig.liveSession.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            print("[API] collab_post応答エラー: \(error)")
            return false
        }
    }

    func fetchCollabResponses(postId: Int) async -> [CollabPostResponse] {
        guard let url = URL(string: ServerConfig.baseURL + "/api/collab_posts/\(postId)/responses") else { return [] }
        do {
            let (data, _) = try await ServerConfig.liveSession.data(from: url)
            return try JSONDecoder().decode([CollabPostResponse].self, from: data)
        } catch {
            print("[API] collab_responses取得エラー: \(error)")
            return []
        }
    }

    func closeCollabPost(postId: Int, beaconId: String) async -> Bool {
        guard let url = URL(string: ServerConfig.baseURL + "/api/collab_posts/\(postId)/close") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["beacon_id": beaconId])
        do {
            let (_, response) = try await ServerConfig.liveSession.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            print("[API] collab_postクローズエラー: \(error)")
            return false
        }
    }

    func fetchInteractionStats(hours: Int = 168) async {
        var components = URLComponents(string: ServerConfig.baseURL + "/api/interaction_stats")!
        components.queryItems = [
            .init(name: "hours", value: String(hours))
        ]
        guard let url = components.url else { return }
        do {
            let (data, _) = try await ServerConfig.liveSession.data(from: url)
            self.interactionStats = try JSONDecoder().decode(InteractionStats.self, from: data)
        } catch {
            print("[API] interaction_stats取得エラー: \(error)")
        }
    }

    func fetchMyInteractions(beaconId: String, days: Int = 7) async {
        var components = URLComponents(string: ServerConfig.baseURL + "/api/my_interactions")!
        components.queryItems = [
            .init(name: "beacon_id", value: beaconId),
            .init(name: "days", value: String(days))
        ]
        guard let url = components.url else { return }
        do {
            let (data, _) = try await ServerConfig.liveSession.data(from: url)
            self.myInteractions = try JSONDecoder().decode(MyInteractions.self, from: data)
        } catch {
            print("[API] my_interactions取得エラー: \(error)")
        }
    }

    func fetchTodaysLunchMatch(beaconId: String) async {
        var components = URLComponents(string: ServerConfig.baseURL + "/api/lunch_match/today")!
        components.queryItems = [
            .init(name: "beacon_id", value: beaconId)
        ]
        guard let url = components.url else { return }
        do {
            let (data, _) = try await ServerConfig.liveSession.data(from: url)
            let response = try JSONDecoder().decode(LunchMatchResponse.self, from: data)
            self.todaysLunchMatch = response.match
        } catch {
            print("[API] lunch_match取得エラー: \(error)")
        }
    }

    func generateLunchMatches(matchType: String = "interest_based") async -> (Bool, String?) {
        guard let url = URL(string: ServerConfig.baseURL + "/api/lunch_match/generate") else { return (false, nil) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["match_type": matchType]
        request.httpBody = try? JSONEncoder().encode(body)
        do {
            let (data, response) = try await ServerConfig.liveSession.data(for: request)
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let message = json["message"] as? String
                return (ok, message)
            }
            return (ok, nil)
        } catch {
            print("[API] lunch_match生成エラー: \(error)")
            return (false, nil)
        }
    }

    func respondToLunchMatch(matchId: Int, beaconId: String, action: String) async -> Bool {
        guard let url = URL(string: ServerConfig.baseURL + "/api/lunch_match/\(matchId)/respond") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "beacon_id": beaconId,
            "action": action
        ]
        request.httpBody = try? JSONEncoder().encode(body)
        do {
            let (_, response) = try await ServerConfig.liveSession.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            print("[API] lunch_match応答エラー: \(error)")
            return false
        }
    }

    func fetchSocialRecommendations(beaconId: String, temp: String, occupancy: String, light: String, nearPerson: String? = nil) async {
        var components = URLComponents(string: ServerConfig.baseURL + "/api/social_recommendations")!
        var items: [URLQueryItem] = [
            .init(name: "beacon_id", value: beaconId),
            .init(name: "temp", value: temp),
            .init(name: "occupancy", value: occupancy),
            .init(name: "light", value: light)
        ]
        if let np = nearPerson, !np.isEmpty {
            items.append(.init(name: "near_person", value: np))
        }
        components.queryItems = items
        guard let url = components.url else { return }
        do {
            let (data, _) = try await ServerConfig.liveSession.data(from: url)
            self.socialRecommendation = try JSONDecoder().decode(SocialRecommendation.self, from: data)
        } catch {
            print("[API] social_recommendations取得エラー: \(error)")
        }
    }
}
