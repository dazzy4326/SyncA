//
//  Models.swift
//  tohata_ios_02
//
//  APIレスポンスのデータモデル
//

import Foundation

// MARK: - センサータイプ
enum SensorType: String, CaseIterable, Identifiable {
    case temp, humidity, lux, co2
    var id: String { rawValue }

    var label: String {
        switch self {
        case .temp:     return "温度"
        case .humidity: return "湿度"
        case .lux:      return "照度"
        case .co2:      return "CO2"
        }
    }

    var unit: String {
        switch self {
        case .temp:     return "°C"
        case .humidity: return "%"
        case .lux:      return "lx"
        case .co2:      return "ppm"
        }
    }

    var gaugeMax: Double {
        switch self {
        case .temp:     return 40
        case .humidity: return 100
        case .lux:      return 1200
        case .co2:      return 1000
        }
    }

    var color: String {
        switch self {
        case .temp:     return "#dc3545"
        case .humidity: return "#17a2b8"
        case .lux:      return "#ffc107"
        case .co2:      return "#28a745"
        }
    }
}

// MARK: - センサーデータ (GET /api/sensor-data)
struct SensorReading: Codable, Identifiable {
    let id: String              // サーバーの "id" キー (e.g. "ras_01")
    let temp: Double?
    let humidity: Double?
    let lux: Double?
    let co2: Double?
    let temperature: Double?    // 代替キー (互換用)
    let illuminance: Double?    // 代替キー (互換用)

    func value(for sensor: SensorType) -> Double {
        switch sensor {
        case .temp:     return temp ?? temperature ?? 0
        case .humidity: return humidity ?? 0
        case .lux:      return lux ?? illuminance ?? 0
        case .co2:      return co2 ?? 0
        }
    }
}

// MARK: - ビーコン位置 (GET /api/get_iphone_positions)
struct PersonPosition: Codable, Identifiable {
    var id: String { beacon_id }
    let beacon_id: String
    let user_name: String?
    let estimated_x: Double?
    let estimated_y: Double?
    let status: String?
    let job_title: String?
    let department: String?
    let profile_image: String?
    let is_moving: Bool?

    private enum CodingKeys: String, CodingKey {
        case beacon_id = "id"
        case user_name = "name"
        case estimated_x = "x"
        case estimated_y = "y"
        case job_title = "job"
        case department = "dept"
        case status
        case profile_image
        case is_moving
    }
}

// MARK: - ユーザープロフィール (GET /api/user_profiles, /api/search_users)
struct UserProfile: Codable, Identifiable {
    var id: String { beacon_id }
    let beacon_id: String
    let user_name: String?
    let job_title: String?
    let department: String?
    let skills: String?
    let hobbies: String?
    let projects: String?
    let email: String?
    let phone: String?
    let profile_image: String?
}

// MARK: - おすすめエリア (GET /api/recommendations)
struct RecommendationResponse: Codable {
    let custom_message: String?
    let static_message: String?
    let best_zone: String?
    let boundaries: ZoneBoundary?
}

struct ZoneBoundary: Codable {
    let x_min: Double
    let x_max: Double
    let y_min: Double
    let y_max: Double
}

// MARK: - アプリ設定 (GET /api/app_config)
struct AppConfig: Codable {
    let PI_LOCATIONS: [PiLocation]?
    let FLOORPLAN_IMAGE: FloorplanImage?
    let CALIBRATION: Calibration?
    let DASHBOARD_SETTINGS: DashboardSettings?
    let ALERT_THRESHOLDS: AlertThresholds?
    let ZONE_BOUNDARIES: [String: ZoneBoundary]?
    let BEACON_POSITIONS: [String: [Double]]?
    let MINOR_ID_TO_PI_NAME_MAP: [String: String]?
    let FLOOR_BOUNDARY: [FloorPoint]?
    let FLOOR_OBJECTS: [FloorObject]?
    let CHAIR_CENTERS: [[Double]]?
    let CENTER_LINES: [CenterLine]?
}

// MARK: - フロア外枠の点
struct FloorPoint: Codable {
    let x: Double
    let y: Double
}

// MARK: - フロアオブジェクト (壁・机・柱・棚・植物・椅子・窓) - 管理者画面で設定
struct FloorObject: Codable {
    let type: String    // "wall", "desk", "pillar", "shelf", "plant", "chair", "monitor", "window"
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double
    let height: Double?
    let height_start: Double?  // 窓ガラス: 高さの始点(mm)
    let label: String?
    let color: String?  // hex色 例: "#FF6600"
    let count: Int?     // 椅子: 直線上に配置する個数
    let rotation: Double? // 椅子: 向き（度数、0=北向き、時計回り）
}

// MARK: - 廊下中心線 (GeoJSON LineString)
struct CenterLine: Codable {
    let type: String
    let coordinates: [[Double]]
}

struct PiLocation: Codable, Identifiable {
    var id: String { "\(piId)" }
    let piId: String
    let x: Double
    let y: Double

    enum CodingKeys: String, CodingKey {
        case piId = "id"
        case x, y
    }
}

struct FloorplanImage: Codable {
    let url: String?
    let width: Double?
    let height: Double?
}

struct Calibration: Codable {
    let origin_px: OriginPx?
    let scale_mm_per_px: Double?
}

struct OriginPx: Codable {
    let x: Double
    let y: Double
}

struct DashboardSettings: Codable {
    let update_interval_ms: Int?
    let max_line_chart_points: Int?
}

struct AlertThresholds: Codable {
    let temp_low: Double?
    let temp_high: Double?
    let humidity_low: Double?
    let humidity_high: Double?
    let lux_low: Double?
    let lux_high: Double?
    let co2_high: Double?
}

// MARK: - 時系列チャート用データポイント
struct ChartPoint: Identifiable {
    let id = UUID()
    let time: String
    let piName: String
    let temp: Double
    let humidity: Double
    let lux: Double
    let co2: Double

    func value(for sensor: SensorType) -> Double {
        switch sensor {
        case .temp:     return temp
        case .humidity: return humidity
        case .lux:      return lux
        case .co2:      return co2
        }
    }
}

// MARK: - ソーシャル機能モデル

struct UserPosition: Codable {
    let x: Double?
    let y: Double?
    let status: String?
    let zone: String?
}

struct SkillSearchResult: Codable, Identifiable {
    var id: String { beacon_id }
    let beacon_id: String
    let user_name: String?
    let department: String?
    let job_title: String?
    let skills: String?
    let matched_skill: String?
    let position: UserPosition?
    let profile_image: String?
}

struct NearbyMatch: Codable, Identifiable {
    var id: String { beacon_id }
    let beacon_id: String
    let user_name: String?
    let distance_mm: Double
    let matching_fields: [String]
    let position: UserPosition?
    let status: String?
    let profile_image: String?
}

struct NearbyMatchResponse: Codable {
    let matches: [NearbyMatch]
}

struct UserAvailability: Codable {
    let beacon_id: String
    let nearby_notify_enabled: Bool?
    let notify_radius_mm: Int?
    let lunch_available: Bool?
    let match_on_skills: Bool?
    let match_on_hobbies: Bool?
}

struct CollabPost: Codable, Identifiable {
    let id: Int
    let beacon_id: String
    let user_name: String?
    let post_type: String
    let title: String
    let description: String?
    let required_skills: String?
    let status: String
    let created_at: String?
    let response_count: Int?
    let profile_image: String?
    let is_skill_match: Bool?
}

struct CollabPostResponse: Codable, Identifiable {
    let id: Int
    let post_id: Int
    let beacon_id: String
    let user_name: String?
    let message: String?
    let created_at: String?
    let profile_image: String?
}

struct InteractionStats: Codable {
    let department_matrix: [String: [String: Int]]?
    let suggestions: [InteractionSuggestion]?
    let zone_heatmap: [String: ZoneInteraction]?
}

struct InteractionSuggestion: Codable, Identifiable {
    var id: String { "\(department_a)_\(department_b)" }
    let department_a: String
    let department_b: String
    let interaction_count: Int
    let suggestion: String
}

struct ZoneInteraction: Codable {
    let total_interactions: Int
    let unique_pairs: Int
}

struct MyInteractions: Codable {
    let frequent_contacts: [FrequentContact]?
    let total_unique_people: Int?
    let most_active_zone: String?
}

struct FrequentContact: Codable, Identifiable {
    var id: String { beacon_id }
    let beacon_id: String
    let user_name: String?
    let interaction_count: Int
    let department: String?
}

struct LunchPartner: Codable {
    let beacon_id: String
    let user_name: String?
    let department: String?
    let job_title: String?
    let skills: String?
    let hobbies: String?
    let profile_image: String?
    let position: UserPosition?
}

struct LunchMatch: Codable, Identifiable {
    let id: Int
    let partner: LunchPartner
    let match_reason: String?
    let status: String
}

struct LunchMatchResponse: Codable {
    let match: LunchMatch?
}

struct LunchGenerateResponse: Codable {
    let matches: [LunchGenerateEntry]?
    let message: String?
}

struct LunchGenerateEntry: Codable, Identifiable {
    let id: Int
    let user_a: LunchUser
    let user_b: LunchUser
    let match_reason: String?
}

struct LunchUser: Codable {
    let beacon_id: String
    let user_name: String?
}

struct SocialRecommendation: Codable {
    let best_zone: String?
    let boundaries: ZoneBoundary?
    let custom_message: String?
    let social_context: SocialContext?
    let environmental_score: Double?
    let social_score: Double?
    let combined_score: Double?
}

struct SocialContext: Codable {
    let near_person_zone: String?
    let near_person_name: String?
    let collaboration_suggestions: [String]?
}
