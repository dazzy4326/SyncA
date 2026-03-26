//
//  ContentView.swift
//  tohata_ios_02
//
//  Created by daichi0208 on 2025/11/13.
//

import SwiftUI
import PhotosUI

// MARK: - アプリテーマカラー (Webアプリと統一)
struct AppTheme {
    static let background = Color(red: 26/255, green: 26/255, blue: 46/255)       // #1a1a2e
    static let cardBackground = Color(red: 44/255, green: 44/255, blue: 84/255)    // #2c2c54
    static let accent = Color(red: 0/255, green: 188/255, blue: 212/255)           // #00bcd4
    static let accentPurple = Color(red: 112/255, green: 111/255, blue: 211/255)   // #706fd3
    static let textPrimary = Color(red: 240/255, green: 240/255, blue: 240/255)    // #f0f0f0
    static let textSecondary = Color(red: 160/255, green: 160/255, blue: 160/255)  // #a0a0a0
    static let tabBarBg = Color(red: 20/255, green: 20/255, blue: 38/255)          // #141426
}

// MARK: - メインビュー (タブベース)
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    // 位置情報許可状態
    @State private var locationAlwaysAuthorized: Bool = false

    @StateObject private var beaconManager = BeaconManager()
    @StateObject private var apiService = APIService()
    @State private var selectedTab: Int = 0

    // ハイライト対象ユーザー (スキル検索 → ダッシュボード連携)
    @State private var highlightTarget: HighlightTarget? = nil
    @State private var scrollToHeatmap: Bool = false

    // ユーザー基本情報
    @AppStorage(UserDefaultsConfig.Keys.userName) private var userName: String = UserDefaultsConfig.defaultUserName
    @AppStorage(UserDefaultsConfig.Keys.userJob) private var userJob: String = UserDefaultsConfig.defaultJobTitle
    @AppStorage(UserDefaultsConfig.Keys.userDept) private var userDept: String = UserDefaultsConfig.defaultDepartment

    // プロフィール詳細
    @AppStorage(UserDefaultsConfig.Keys.userSkills) private var userSkills: String = ""
    @AppStorage(UserDefaultsConfig.Keys.userHobbies) private var userHobbies: String = ""
    @AppStorage(UserDefaultsConfig.Keys.userProjects) private var userProjects: String = ""
    @AppStorage(UserDefaultsConfig.Keys.userEmail) private var userEmail: String = ""
    @AppStorage(UserDefaultsConfig.Keys.userPhone) private var userPhone: String = ""

    // オンボーディング: タブごとの初回表示フラグ
    @AppStorage("tabGuide_seen_0") private var seenTab0 = false
    @AppStorage("tabGuide_seen_1") private var seenTab1 = false
    @AppStorage("tabGuide_seen_2") private var seenTab2 = false
    @AppStorage("tabGuide_seen_3") private var seenTab3 = false
    @AppStorage("tabGuide_seen_4") private var seenTab4 = false
    @State private var showingTabGuide = false

    var body: some View {
        ZStack(alignment: .bottom) {
            AppTheme.background.ignoresSafeArea()

            if locationAlwaysAuthorized {
                // メインコンテンツ
                TabView(selection: $selectedTab) {
                    DashboardTab(apiService: apiService, beaconManager: beaconManager, highlightTarget: $highlightTarget, scrollToHeatmap: $scrollToHeatmap)
                        .tag(0)
                    SocialTab(
                        apiService: apiService,
                        beaconId: beaconManager.deviceID,
                        onHighlightUser: { target in
                            highlightTarget = target
                            if target.x != nil && target.y != nil {
                                selectedTab = 0
                                // タブ遷移後にスクロール
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    scrollToHeatmap = true
                                }
                            }
                        }
                    )
                        .tag(1)
                    ProfileTab(
                        beaconManager: beaconManager,
                        userName: $userName,
                        userJob: $userJob,
                        userDept: $userDept,
                        userSkills: $userSkills,
                        userHobbies: $userHobbies,
                        userProjects: $userProjects,
                        userEmail: $userEmail,
                        userPhone: $userPhone
                    )
                        .tag(2)
                    PositioningTab(beaconManager: beaconManager)
                        .tag(3)
                    AdminTab(apiService: apiService)
                        .tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea(.container, edges: .bottom)

                // カスタムタブバー
                CustomTabBar(selectedTab: $selectedTab)
            } else {
                // 許可されていない場合のビジュアル手順案内View
                VStack(spacing: 24) {
                    Spacer()
                    Image(systemName: "location.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.red)
                    Text("位置情報の設定が『常に許可』になっていません")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            Text("①")
                                .font(.title2.weight(.bold))
                                .foregroundColor(.accentColor)
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.accentColor)
                            Text("設定アプリを開く")
                                .font(.body.weight(.bold))
                                .foregroundColor(.white)
                        }
                        HStack(spacing: 12) {
                            Text("②")
                                .font(.title2.weight(.bold))
                                .foregroundColor(.accentColor)
                            Image(systemName: "hand.point.right.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.accentColor)
                            Text("プライバシー > 位置情報サービス > アプリ名 を選択")
                                .font(.body.weight(.bold))
                                .foregroundColor(.white)
                        }
                        HStack(spacing: 12) {
                            Text("③")
                                .font(.title2.weight(.bold))
                                .foregroundColor(.accentColor)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.accentColor)
                            Text("『常に許可』を選択")
                                .font(.body.weight(.bold))
                                .foregroundColor(.white)
                        }
                        HStack(spacing: 12) {
                            Text("④")
                                .font(.title2.weight(.bold))
                                .foregroundColor(.accentColor)
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.accentColor)
                            Text("設定後、アプリを再起動")
                                .font(.body.weight(.bold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.15))
                    .cornerRadius(12)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.background)
            }
        }
        .onAppear {
            beaconManager.currentUserName = userName
            beaconManager.currentJobTitle = userJob
            beaconManager.currentDepartment = userDept
            checkTabGuide(for: selectedTab)
            // 位置情報許可状態チェック
            checkLocationAuthorization()
        }
        .onChange(of: selectedTab) { _, newTab in
            checkTabGuide(for: newTab)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                checkLocationAuthorization()
            }
        }
        .overlay {
            if showingTabGuide {
                TabGuideOverlay(tabIndex: selectedTab, onDismiss: {
                    markTabSeen(selectedTab)
                    showingTabGuide = false
                })
            }
        }
        // 接続エラーバナー
        .overlay(alignment: .top) {
            if !beaconManager.isServerConnected {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .font(.caption)
                    Text("サーバー未接続")
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(Color.red.opacity(0.9))
                .foregroundColor(.white)
                .transition(.move(edge: .top))
                .animation(.easeInOut, value: beaconManager.isServerConnected)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // 位置情報許可状態チェック
    private func checkLocationAuthorization() {
        let status = CLLocationManager.authorizationStatus()
        locationAlwaysAuthorized = (status == .authorizedAlways)
    }

    private func isTabSeen(_ index: Int) -> Bool {
        switch index {
        case 0: return seenTab0
        case 1: return seenTab1
        case 2: return seenTab2
        case 3: return seenTab3
        case 4: return seenTab4
        default: return true
        }
    }

    private func markTabSeen(_ index: Int) {
        switch index {
        case 0: seenTab0 = true
        case 1: seenTab1 = true
        case 2: seenTab2 = true
        case 3: seenTab3 = true
        case 4: seenTab4 = true
        default: break
        }
    }

    private func checkTabGuide(for index: Int) {
        if !isTabSeen(index) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showingTabGuide = true
            }
        }
    }
}

// MARK: - カスタムタブバー
struct CustomTabBar: View {
    @Binding var selectedTab: Int

    private let tabs: [(icon: String, label: String)] = [
        ("chart.bar.doc.horizontal", "ダッシュボード"),
        ("person.2.circle", "ソーシャル"),
        ("person.circle", "プロフィール"),
        ("location.circle", "測位"),
        ("gearshape", "管理者")
    ]

    var body: some View {
        HStack {
            ForEach(0..<tabs.count, id: \.self) { index in
                Button(action: { selectedTab = index }) {
                    VStack(spacing: 4) {
                        Image(systemName: tabs[index].icon)
                            .font(.system(size: 20))
                        Text(tabs[index].label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(selectedTab == index ? AppTheme.accent : AppTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 20)
        .background(
            AppTheme.tabBarBg
                .shadow(color: .black.opacity(0.4), radius: 8, y: -4)
        )
    }
}

// MARK: - ハイライト対象
struct HighlightTarget: Equatable {
    let beaconId: String
    let userName: String?
    let x: Double?  // mm (位置不明ならnil)
    let y: Double?  // mm
}

// MARK: - ダッシュボードタブ (ネイティブ)
struct DashboardTab: View {
    @ObservedObject var apiService: APIService
    @ObservedObject var beaconManager: BeaconManager
    @Binding var highlightTarget: HighlightTarget?
    @Binding var scrollToHeatmap: Bool

    var body: some View {
        NativeDashboardView(apiService: apiService, activeBeaconMinors: beaconManager.activeBeaconMinors, highlightTarget: $highlightTarget, scrollToHeatmap: $scrollToHeatmap)
    }
}

// MARK: - 測位タブ
struct PositioningTab: View {
    @ObservedObject var beaconManager: BeaconManager
    @State private var showDebugLog = false
    @State private var showServerSettings = false
    @State private var serverURL = ""
    @State private var isScanning = false

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(title: "測位ステータス")

            ScrollView {
                VStack(spacing: 12) {

                    // 1. 測位フェーズインジケーター
                    phaseCard

                    // 2. 動作ステータス + 推定位置
                    motionAndPositionCard

                    // 3. ビーコン別収集進捗
                    beaconProgressCard

                    // 4. 接続ステータス
                    connectionCard

                    // 5. デバッグログ (折りたたみ)
                    debugLogCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 100)
            }
        }
        .background(AppTheme.background)
    }

    // MARK: - 測位フェーズ
    private var phaseCard: some View {
        CardView {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(phaseColor.opacity(0.15))
                            .frame(width: 48, height: 48)
                        Image(systemName: phaseIcon)
                            .font(.title2)
                            .foregroundColor(phaseColor)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(beaconManager.positioningPhase.rawValue)
                            .font(.headline)
                            .foregroundColor(AppTheme.textPrimary)
                        Text(phaseDescription)
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    Spacer()
                }
                // 全体進捗バー
                let totalRequired = BeaconConfig.coordinates.count
                let readyCount = beaconManager.medianReadyCount
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("中央値確定")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        Text("\(readyCount) / \(totalRequired) 台")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(readyCount >= totalRequired ? .green : AppTheme.accent)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.1)).frame(height: 6)
                            Capsule().fill(readyCount >= totalRequired ? Color.green : AppTheme.accent)
                                .frame(width: geo.size.width * CGFloat(readyCount) / CGFloat(max(totalRequired, 1)), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
    }

    // MARK: - 動作 + 推定位置
    private var motionAndPositionCard: some View {
        CardView {
            HStack(spacing: 16) {
                // 動作ステータス
                VStack(spacing: 4) {
                    Image(systemName: beaconManager.isUserMoving ? "figure.walk" : "figure.stand")
                        .font(.title3)
                        .foregroundColor(beaconManager.isUserMoving ? .orange : .green)
                    Text(beaconManager.isUserMoving ? "移動中" : "静止中")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .frame(width: 56)

                Divider().frame(height: 40)

                // 推定位置
                VStack(alignment: .leading, spacing: 2) {
                    Text("推定位置")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textSecondary)
                    if let pos = beaconManager.estimatedPosition {
                        Text("X: \(Int(pos.x)) mm  Y: \(Int(pos.y)) mm")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(AppTheme.textPrimary)
                    } else {
                        Text("未測位")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }

                Spacer()

                // 最終測位時刻
                VStack(alignment: .trailing, spacing: 2) {
                    Text("最終測位")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textSecondary)
                    if let t = beaconManager.lastPositionedAt {
                        Text(timeAgoText(t))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.accent)
                    } else {
                        Text("---")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - ビーコン別進捗
    private var beaconProgressCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sensor.tag.radiowaves.forward")
                        .foregroundColor(AppTheme.accent)
                    Text("ビーコン別サンプル収集")
                        .font(.caption.weight(.bold))
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                    Text("検出: \(beaconManager.activeBeaconMinors.count)台")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.accent)
                }

                let sortedMinors = BeaconConfig.coordinates.keys.sorted()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(sortedMinors, id: \.self) { minor in
                        beaconCell(minor: minor)
                    }
                }
            }
        }
    }

    private func beaconCell(minor: Int) -> some View {
        let progress = beaconManager.beaconSampleProgress[minor]
        let current = progress?.current ?? 0
        let required = progress?.required ?? BeaconConfig.sampleCount
        let isActive = beaconManager.activeBeaconMinors.contains(minor)
        let isComplete = current >= required
        let ratio = CGFloat(current) / CGFloat(max(required, 1))

        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(isComplete ? Color.green : (isActive ? AppTheme.accent : Color.gray.opacity(0.4)))
                    .frame(width: 6, height: 6)
                Text("#\(minor)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(isActive ? AppTheme.textPrimary : AppTheme.textSecondary)
            }
            // ミニプログレスバー
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 4)
                    Capsule().fill(isComplete ? Color.green : AppTheme.accent)
                        .frame(width: geo.size.width * ratio, height: 4)
                }
            }
            .frame(height: 4)
            Text("\(current)/\(required)")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(AppTheme.textSecondary)
        }
        .padding(6)
        .background(Color.black.opacity(isActive ? 0.2 : 0.1))
        .cornerRadius(6)
    }

    // MARK: - 接続ステータス + サーバー設定
    private var connectionCard: some View {
        CardView {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: beaconManager.isServerConnected ? "wifi" : "wifi.slash")
                        .font(.title3)
                        .foregroundColor(beaconManager.isServerConnected ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("サーバー接続")
                            .font(.caption.weight(.bold))
                            .foregroundColor(AppTheme.textSecondary)
                        Text(beaconManager.isServerConnected ? "接続中" : "切断")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(beaconManager.isServerConnected ? .green : .red)
                    }
                    Spacer()
                    // 接続モードバッジ
                    Text(ServerConfig.connectionMode)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ServerConfig.isLAN ? Color.green : Color.purple)
                        .cornerRadius(4)
                    Button(action: { withAnimation { showServerSettings.toggle() } }) {
                        Image(systemName: "gearshape")
                            .font(.body)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                // 接続先URL表示
                Text(ServerConfig.baseURL)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)

                // サーバー設定パネル
                if showServerSettings {
                    VStack(spacing: 8) {
                        Divider().background(Color.white.opacity(0.1))

                        // LAN自動検出ボタン
                        Button {
                            isScanning = true
                            Task {
                                if let found = await ServerConfig.detectLANServer() {
                                    ServerConfig.setBaseURL(found)
                                    serverURL = found
                                }
                                isScanning = false
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if isScanning {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.7)
                                } else {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                }
                                Text(isScanning ? "LAN検索中..." : "LANサーバーを自動検出")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.7))
                            .cornerRadius(6)
                        }
                        .disabled(isScanning)

                        Text("URL手入力（ngrok / LAN IP）")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textSecondary)
                        HStack {
                            TextField("http://192.168.x.x:5000", text: $serverURL)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(AppTheme.textPrimary)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .padding(8)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(6)
                            Button("設定") {
                                let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
                                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                                if !trimmed.isEmpty {
                                    ServerConfig.setBaseURL(trimmed)
                                }
                                withAnimation { showServerSettings = false }
                            }
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppTheme.accent)
                            .cornerRadius(6)
                        }
                        // ngrokにリセット
                        Button(action: {
                            ServerConfig.resetToNgrok()
                            serverURL = ""
                            withAnimation { showServerSettings = false }
                        }) {
                            HStack {
                                Image(systemName: "arrow.uturn.backward")
                                Text("ngrokに戻す")
                            }
                            .font(.caption)
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
        }
        .onAppear {
            let current = ServerConfig.baseURL
            if current != ServerConfig.ngrokURL {
                serverURL = current
            }
        }
    }

    // MARK: - デバッグログ (折りたたみ)
    private var debugLogCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: { withAnimation { showDebugLog.toggle() } }) {
                    HStack {
                        Image(systemName: "terminal")
                            .foregroundColor(AppTheme.accentPurple)
                        Text("デバッグログ")
                            .font(.caption.weight(.bold))
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        Image(systemName: showDebugLog ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                .buttonStyle(.plain)

                if showDebugLog {
                    ScrollView {
                        Text(beaconManager.logMessage)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 150)
                    .padding(8)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - ヘルパー
    private var phaseColor: Color {
        switch beaconManager.positioningPhase {
        case .initializing:        return .gray
        case .scanning:            return .orange
        case .collecting:          return AppTheme.accent
        case .calculating:         return .yellow
        case .positioned:          return .green
        case .movingSkipped:       return .orange
        case .insufficientBeacons: return .red
        }
    }

    private var phaseIcon: String {
        switch beaconManager.positioningPhase {
        case .initializing:        return "gear"
        case .scanning:            return "antenna.radiowaves.left.and.right"
        case .collecting:          return "waveform.path.ecg"
        case .calculating:         return "function"
        case .positioned:          return "mappin.and.ellipse"
        case .movingSkipped:       return "figure.walk"
        case .insufficientBeacons: return "exclamationmark.triangle"
        }
    }

    private var phaseDescription: String {
        switch beaconManager.positioningPhase {
        case .initializing:        return "システムを初期化しています"
        case .scanning:            return "周囲のビーコンを探しています"
        case .collecting:          return "距離サンプルを収集しています"
        case .calculating:         return "位置を計算しています"
        case .positioned:          return "測位完了"
        case .movingSkipped:       return "移動中のため測位をスキップ"
        case .insufficientBeacons: return "\(BeaconConfig.requiredBeaconCount)台の中央値が必要です"
        }
    }

    private func timeAgoText(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "たった今" }
        if seconds < 60 { return "\(seconds)秒前" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)分前" }
        return "\(minutes / 60)時間前"
    }
}

// MARK: - プロフィールタブ
struct ProfileTab: View {
    @ObservedObject var beaconManager: BeaconManager

    @Binding var userName: String
    @Binding var userJob: String
    @Binding var userDept: String
    @Binding var userSkills: String
    @Binding var userHobbies: String
    @Binding var userProjects: String
    @Binding var userEmail: String
    @Binding var userPhone: String

    let jobOptions = PickerOptions.jobOptions
    let deptOptions = PickerOptions.deptOptions

    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var profileImageData: Data? = nil
    @State private var saveMessage = ""
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(title: "プロフィール設定")

            ScrollView {
                VStack(spacing: 16) {

                    // アバターカード
                    CardView {
                        VStack(spacing: 12) {
                            ZStack(alignment: .bottomTrailing) {
                                if let data = profileImageData, let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(AppTheme.accent, lineWidth: 2))
                                } else {
                                    Circle()
                                        .fill(AppTheme.accentPurple.opacity(0.3))
                                        .frame(width: 80, height: 80)
                                        .overlay(
                                            Text(String(userName.prefix(1)).uppercased())
                                                .font(.title)
                                                .fontWeight(.bold)
                                                .foregroundColor(AppTheme.textPrimary)
                                        )
                                        .overlay(Circle().stroke(AppTheme.accent, lineWidth: 2))
                                }
                                // ステータスランプ
                                Circle()
                                    .fill(profileStatusColor(beaconManager.currentStatus))
                                    .frame(width: 18, height: 18)
                                    .overlay(Circle().stroke(AppTheme.cardBackground, lineWidth: 2.5))
                                    .shadow(color: profileStatusColor(beaconManager.currentStatus).opacity(0.6), radius: 3)
                            }

                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Text("画像を変更")
                                    .font(.caption)
                                    .foregroundColor(AppTheme.accent)
                            }
                            .onChange(of: selectedPhoto) { _, newItem in
                                Task {
                                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                        profileImageData = data
                                    }
                                }
                            }
                        }
                    }

                    // ステータス設定カード
                    CardView {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(text: "ステータス")
                            Picker("Status", selection: $beaconManager.currentStatus) {
                                ForEach(PickerOptions.statusOptions, id: \.0) { option in
                                    Text(option.1).tag(option.0)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                    }
                    // 基本情報カード
                    CardView {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionLabel(text: "基本情報")

                            ProfileTextField(label: "名前", text: $userName, icon: "person")
                                .onChange(of: userName) { _, val in beaconManager.currentUserName = val }

                            ProfilePickerField(label: "職種", selection: $userJob, options: jobOptions, icon: "briefcase")
                                .onChange(of: userJob) { _, val in beaconManager.currentJobTitle = val }

                            ProfilePickerField(label: "部署", selection: $userDept, options: deptOptions, icon: "building.2")
                                .onChange(of: userDept) { _, val in beaconManager.currentDepartment = val }
                        }
                    }

                    // 詳細情報カード
                    CardView {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionLabel(text: "詳細情報")

                            ProfileTextField(label: "スキル", text: $userSkills, icon: "star", placeholder: "カンマ区切りで入力")
                            ProfileTextField(label: "趣味", text: $userHobbies, icon: "heart", placeholder: "カンマ区切りで入力")
                            ProfileTextField(label: "PJ経験", text: $userProjects, icon: "folder", placeholder: "カンマ区切りで入力")
                        }
                    }

                    // 連絡先カード
                    CardView {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionLabel(text: "連絡先")

                            ProfileTextField(label: "メール", text: $userEmail, icon: "envelope", keyboardType: .emailAddress)
                            ProfileTextField(label: "電話", text: $userPhone, icon: "phone", keyboardType: .phonePad)
                        }
                    }

                    // 保存ボタン
                    Button(action: saveProfile) {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(isSaving ? "保存中..." : "プロフィールを保存")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppTheme.accent)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isSaving)
                    .padding(.horizontal, 4)

                    if !saveMessage.isEmpty {
                        Text(saveMessage)
                            .font(.caption)
                            .foregroundColor(saveMessage.contains("成功") ? .green : .red)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 100)
            }
        }
        .background(AppTheme.background)
    }

    private func saveProfile() {
        isSaving = true
        saveMessage = ""

        if let imageData = profileImageData,
           let compressed = UIImage(data: imageData)?.jpegData(compressionQuality: 0.7) {
            beaconManager.uploadProfileImage(imageData: compressed) { success, imageUrl in
                DispatchQueue.main.async {
                    if success {
                        print("[Profile] 画像アップロード成功: \(imageUrl ?? "")")
                    }
                }
            }
        }

        beaconManager.sendProfileToServer(
            skills: userSkills,
            hobbies: userHobbies,
            projects: userProjects,
            email: userEmail,
            phone: userPhone
        ) { success in
            DispatchQueue.main.async {
                isSaving = false
                saveMessage = success ? "保存に成功しました" : "保存に失敗しました"
                if success {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        saveMessage = ""
                    }
                }
            }
        }
    }

    private func profileStatusColor(_ status: String) -> Color {
        switch status {
        case "available": return .green
        case "busy":      return .red
        case "meeting":   return .orange
        case "break":     return .blue
        default:          return .gray
        }
    }
}

// MARK: - 共通コンポーネント

/// ヘッダーバー
struct HeaderBar: View {
    let title: String
    var onRefresh: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundColor(AppTheme.textPrimary)

            Spacer()

            if let onRefresh = onRefresh {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.body)
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.background)
    }
}

/// カードビュー
struct CardView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(AppTheme.cardBackground)
            .cornerRadius(12)
    }
}



/// セクションラベル
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundColor(AppTheme.accent)
            .textCase(.uppercase)
    }
}

/// プロフィール入力フィールド
struct ProfileTextField: View {
    let label: String
    @Binding var text: String
    var icon: String = "text.cursor"
    var placeholder: String = ""
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(AppTheme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary)
                TextField(placeholder.isEmpty ? label : placeholder, text: $text)
                    .font(.body)
                    .foregroundColor(AppTheme.textPrimary)
                    .keyboardType(keyboardType)
                    .autocorrectionDisabled()
            }
        }
        .padding(.vertical, 4)
    }
}

/// プロフィールピッカーフィールド
struct ProfilePickerField: View {
    let label: String
    @Binding var selection: String
    let options: [(String, String)]
    var icon: String = "chevron.down"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(AppTheme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary)
                Picker(label, selection: $selection) {
                    ForEach(options, id: \.0) { option in
                        Text(option.1).tag(option.0)
                    }
                }
                .labelsHidden()
                .tint(AppTheme.textPrimary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - プレビュー
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

// MARK: - タブ別ガイドオーバーレイ
struct TabGuideOverlay: View {
    let tabIndex: Int
    let onDismiss: () -> Void

    private struct GuideContent {
        let icon: String
        let title: String
        let description: String
    }

    private var content: GuideContent {
        switch tabIndex {
        case 0:
            return GuideContent(
                icon: "chart.bar.doc.horizontal",
                title: "ダッシュボード",
                description: "室内の温度・湿度・照度・CO2をリアルタイムで確認できます。ヒートマップで環境分布を可視化し、お好みに合ったエリアをおすすめします。下にスワイプでデータを更新できます。"
            )
        case 1:
            return GuideContent(
                icon: "location.circle",
                title: "測位",
                description: "BLEビーコンを使って室内の位置を自動で推定します。ビーコンからの距離サンプルを収集し、三点測位で現在地を計算します。"
            )
        case 2:
            return GuideContent(
                icon: "person.circle",
                title: "プロフィール",
                description: "名前・部署・スキルなどを設定してください。設定した情報はスキルマッチングやランチマッチングに活用されます。"
            )
        case 3:
            return GuideContent(
                icon: "person.2.circle",
                title: "ソーシャル",
                description: "スキル検索・コラボボード・ランチマッチング・部門間の交流分析など、チームのつながりを促進する機能が揃っています。下にスワイプでデータを更新できます。"
            )
        case 4:
            return GuideContent(
                icon: "gearshape",
                title: "管理者",
                description: "サーバー接続やビーコン設定など、アプリの管理機能にアクセスできます。"
            )
        default:
            return GuideContent(icon: "questionmark.circle", title: "", description: "")
        }
    }

    var body: some View {
        ZStack {
            // 半透明の背景
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // ガイドパネル
            VStack(spacing: 20) {
                Image(systemName: content.icon)
                    .font(.system(size: 44))
                    .foregroundColor(AppTheme.accent)

                Text(content.title)
                    .font(.title3.weight(.bold))
                    .foregroundColor(AppTheme.textPrimary)

                Text(content.description)
                    .font(.subheadline)
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onDismiss) {
                    Text("OK")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.accent)
                        .cornerRadius(10)
                }
            }
            .padding(24)
            .background(AppTheme.cardBackground)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
            .padding(.horizontal, 32)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.25), value: true)
    }
}
