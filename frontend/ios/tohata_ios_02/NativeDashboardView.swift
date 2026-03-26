//
//  NativeDashboardView.swift
//  tohata_ios_02
//
//  Webアプリのスマートフォン表示をSwiftUIネイティブで再現
//

import SwiftUI
import Charts
import Combine

// MARK: - セクション定義 (Webアプリのナビゲーションと一致)
enum DashboardSection: String, CaseIterable, Identifiable {
    case heatmap = "ヒートマップ"
    case preference = "お好み選択"
    case timeseries = "時系列トレンド"
    case distribution = "拠点別比較"

    var id: String { rawValue }
}

// MARK: - メインダッシュボード
struct NativeDashboardView: View {
    @ObservedObject var apiService: APIService
    var activeBeaconMinors: Set<Int>
    @Binding var highlightTarget: HighlightTarget?
    @Binding var scrollToHeatmap: Bool
    @State private var selectedSensor: SensorType = .temp
    @State private var overviewSensor: SensorType = .temp
    @State private var lineSensor: SensorType = .temp
    @State private var barSensor: SensorType = .temp
    @State private var avgSensor: SensorType = .temp

    // お好み選択
    @State private var prefTemp = "any"
    @State private var prefOccupancy = "any"
    @State private var prefLight = "any"
    @State private var prefHumidity = "any"
    @State private var prefCo2 = "any"

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダーs
            DashboardHeader()

            // セクションナビゲーション (Webアプリと同じ)
            ScrollViewReader { proxy in
                SectionNavBar(onTap: { section in
                    withAnimation {
                        proxy.scrollTo(section, anchor: .top)
                    }
                })

                ScrollView {
                    VStack(spacing: 14) {
                        // ユーザー検索 (常時表示)
                        UserSearchSection(apiService: apiService, highlightTarget: $highlightTarget)

                        // センサー概要カード
                        SensorOverviewSection(data: apiService.sensorData, sensor: $overviewSensor, activeBeaconMinors: activeBeaconMinors)

                        // ヒートマップ (フロアマップ + IDWオーバーレイ)
                        HeatmapSection(apiService: apiService, sensor: $selectedSensor, highlightTarget: $highlightTarget)
                            .id(DashboardSection.heatmap)

                        // お好み選択 + 全体平均 (横並び)
                        HStack(alignment: .top, spacing: 10) {
                            PreferenceSection(
                                prefTemp: $prefTemp,
                                prefOccupancy: $prefOccupancy,
                                prefLight: $prefLight,
                                prefHumidity: $prefHumidity,
                                prefCo2: $prefCo2,
                                onUpdate: {
                                    Task {
                                        await apiService.fetchRecommendations(
                                            temp: prefTemp, occupancy: prefOccupancy, light: prefLight,
                                            humidity: prefHumidity, co2: prefCo2
                                        )
                                    }
                                }
                            )
                            .frame(maxWidth: .infinity)

                            AverageGaugeSection(apiService: apiService, sensor: $avgSensor)
                                .frame(maxWidth: .infinity)
                        }
                        .id(DashboardSection.preference)

                        // 時系列トレンド
                        LineChartSection(apiService: apiService, sensor: $lineSensor)
                            .id(DashboardSection.timeseries)

                        // 拠点別比較
                        BarChartSection(data: apiService.sensorData, sensor: $barSensor)
                            .id(DashboardSection.distribution)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
                .refreshable {
                    apiService.refreshData()
                    await apiService.fetchRecommendations(
                        temp: prefTemp, occupancy: prefOccupancy, light: prefLight,
                        humidity: prefHumidity, co2: prefCo2
                    )
                }
                .onChange(of: scrollToHeatmap) { newValue in
                    if newValue {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                proxy.scrollTo(DashboardSection.heatmap, anchor: .top)
                            }
                            scrollToHeatmap = false
                        }
                    }
                }
                .onChange(of: highlightTarget) { newValue in
                    // ハイライト対象が設定されたらヒートマップへスクロール
                    if let target = newValue, target.x != nil, target.y != nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                proxy.scrollTo(DashboardSection.heatmap, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .background(AppTheme.background)
        .task {
            await apiService.fetchConfigAsync()
            apiService.startAutoRefresh()
        }
        .onDisappear {
            apiService.stopAutoRefresh()
        }
    }
}

// MARK: - ヘッダー (SyncAブランド + 時計)
struct DashboardHeader: View {
    @State private var currentTime = ""
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack {
            // ロゴ + アプリ名
            HStack(spacing: 8) {
                Image(systemName: "circle.hexagongrid")
                    .font(.title3)
                    .foregroundColor(AppTheme.accent)
                Text("SyncA")
                    .font(.title2.weight(.bold))
                    .foregroundColor(AppTheme.textPrimary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.background)
        
    }
}

// MARK: - セクションナビゲーションバー (Webアプリと同じ)
struct SectionNavBar: View {
    var onTap: (DashboardSection) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(DashboardSection.allCases) { section in
                    Button {
                        onTap(section)
                    } label: {
                        Text(section.rawValue)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color(hex: "#40407a"))
                            .foregroundColor(AppTheme.textPrimary)
                            .cornerRadius(4)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(
            AppTheme.background.opacity(0.92)
        )
    }
}

// MARK: - センサー概要
struct SensorOverviewSection: View {
    let data: [SensorReading]
    @Binding var sensor: SensorType
    var activeBeaconMinors: Set<Int>

    /// "ras_01" → 1, "ras_02" → 2, etc.
    private func minorId(from piId: String) -> Int? {
        let digits = piId.filter { $0.isNumber }
        return Int(digits)
    }

    var body: some View {
        DashboardCard(title: "リアルタイムセンサー") {
            // センサータブ
            SensorMiniTabs(selected: $sensor)

            if data.isEmpty {
                HStack {
                    ProgressView().tint(AppTheme.accent)
                    Text("データ取得中...")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                }
                .padding()
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(data) { reading in
                        let val = reading.value(for: sensor)
                        let isActive = minorId(from: reading.id).map { activeBeaconMinors.contains($0) } ?? false
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(isActive ? Color.green : Color.gray.opacity(0.4))
                                    .frame(width: 7, height: 7)
                                Text(reading.id)
                                    .font(.caption2)
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            Text(String(format: "%.1f", val))
                                .font(.system(size: 22, weight: .bold, design: .monospaced))
                                .foregroundColor(AppTheme.accent)
                            Text(sensor.unit)
                                .font(.caption2)
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.15))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }
}

// MARK: - ヒートマップセクション (IDW補間 + フロアマップ)
struct HeatmapSection: View {
    @ObservedObject var apiService: APIService
    @Binding var sensor: SensorType
    @Binding var highlightTarget: HighlightTarget?
    @State private var is3DMode = false

    var body: some View {
        DashboardCard(title: "リアルタイムヒートマップ") {
            // センサー切替タブ + 2D/3Dトグル
            HStack {
                SensorMiniTabs(selected: $sensor)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { is3DMode.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: is3DMode ? "square.split.2x2" : "cube")
                            .font(.system(size: 10, weight: .bold))
                        Text(is3DMode ? "2D" : "3D")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(is3DMode ? AppTheme.accent.opacity(0.3) : Color.white.opacity(0.1))
                    .foregroundColor(is3DMode ? AppTheme.accent : AppTheme.textSecondary)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(is3DMode ? AppTheme.accent.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                }
            }

            FloorMap3DView(
                appConfig: apiService.appConfig,
                sensorData: apiService.sensorData,
                persons: apiService.persons,
                sensor: sensor,
                floorplanURL: apiService.floorplanURL(),
                isTopDown: !is3DMode,
                highlightTarget: highlightTarget,
                recommendation: apiService.recommendation
            )
            .frame(height: 400)
            .cornerRadius(8)
            .clipped()
            .onTapGesture {
                // ハイライト解除
                if highlightTarget != nil {
                    withAnimation { highlightTarget = nil }
                }
            }

            // おすすめエリア案内
            if let rec = apiService.recommendation, let best = rec.best_zone, !best.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                    Text("お客様の好みには\(best)が最適です")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)
            }

            // カラーバー凡例
            colorBar

            // 人数カウント + 在室者リスト
            occupantsSection
        }
    }

    private func colormapColor(for sensor: SensorType, t: Double) -> Color {
        switch sensor {
        case .temp:
            // 青 → 水色 → 緑 → 黄 → 橙 → 赤
            let stops: [(Double, Double, Double, Double)] = [
                (0.0, 0.0, 0.0, 0.6),
                (0.2, 0.0, 0.5, 1.0),
                (0.4, 0.0, 0.8, 0.4),
                (0.6, 1.0, 1.0, 0.0),
                (0.8, 1.0, 0.5, 0.0),
                (1.0, 0.8, 0.0, 0.0)
            ]
            return interpolateStops(stops, t)
        case .humidity:
            let stops: [(Double, Double, Double, Double)] = [
                (0.0, 0.9, 0.9, 0.5),
                (0.5, 0.3, 0.6, 0.9),
                (1.0, 0.0, 0.1, 0.6)
            ]
            return interpolateStops(stops, t)
        case .lux:
            let stops: [(Double, Double, Double, Double)] = [
                (0.0, 0.15, 0.0, 0.3),
                (0.5, 0.8, 0.5, 0.1),
                (1.0, 1.0, 1.0, 0.3)
            ]
            return interpolateStops(stops, t)
        case .co2:
            let stops: [(Double, Double, Double, Double)] = [
                (0.0, 0.1, 0.7, 0.2),
                (0.5, 0.9, 0.8, 0.1),
                (1.0, 0.8, 0.1, 0.1)
            ]
            return interpolateStops(stops, t)
        }
    }

    private func interpolateStops(_ stops: [(Double, Double, Double, Double)], _ t: Double) -> Color {
        guard stops.count >= 2 else { return .clear }
        for i in 0..<stops.count - 1 {
            if t >= stops[i].0 && t <= stops[i + 1].0 {
                let f = (t - stops[i].0) / (stops[i + 1].0 - stops[i].0)
                let r = stops[i].1 + f * (stops[i + 1].1 - stops[i].1)
                let g = stops[i].2 + f * (stops[i + 1].2 - stops[i].2)
                let b = stops[i].3 + f * (stops[i + 1].3 - stops[i].3)
                return Color(red: r, green: g, blue: b)
            }
        }
        let last = stops.last!
        return Color(red: last.1, green: last.2, blue: last.3)
    }

    private var colorBar: some View {
        VStack(spacing: 2) {
            // グラデーションバー
            GeometryReader { geo in
                Canvas { context, size in
                    let steps = 100
                    let cellW = size.width / Double(steps)
                    for i in 0..<steps {
                        let t = Double(i) / Double(steps)
                        let color = colormapColor(for: sensor, t: t)
                        let rect = CGRect(x: Double(i) * cellW, y: 0, width: cellW + 0.5, height: size.height)
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
            .frame(height: 12)
            .cornerRadius(3)

            // ラベル
            HStack {
                Text(colorBarMin)
                    .font(.system(size: 9))
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
                Text(colorBarMax)
                    .font(.system(size: 9))
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
        .padding(.horizontal, 4)
    }

    private var colorBarMin: String {
        let values = apiService.sensorData.compactMap { $0.value(for: sensor) }
        guard let m = values.min() else { return "--" }
        return String(format: "%.1f%@", m, sensor.unit)
    }

    private var colorBarMax: String {
        let values = apiService.sensorData.compactMap { $0.value(for: sensor) }
        guard let m = values.max() else { return "--" }
        return String(format: "%.1f%@", m, sensor.unit)
    }

    private var occupantsSection: some View {
        Group {
            if !apiService.persons.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("在室者")
                            .font(.caption.weight(.bold))
                            .foregroundColor(AppTheme.accent)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                                .font(.caption2)
                            Text("\(apiService.persons.count)人")
                                .font(.caption2.weight(.bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppTheme.accent.opacity(0.2))
                        .foregroundColor(AppTheme.accent)
                        .cornerRadius(10)
                    }
                    // パルス解除ボタン
                    if highlightTarget != nil {
                        Button {
                            highlightTarget = nil
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                Text("パルス表示を解除")
                            }
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.6))
                            .cornerRadius(6)
                        }
                    }

                    ForEach(apiService.persons) { person in
                        HStack(spacing: 8) {
                            // アバター + ステータスランプ（タップでハイライト）
                            ZStack(alignment: .bottomTrailing) {
                                if let imgPath = person.profile_image,
                                   let url = URL(string: ServerConfig.baseURL + imgPath) {
                                    CachedAsyncImage(url: url) { img in
                                        img.resizable().scaledToFill()
                                    } placeholder: {
                                        initialsCircle(person.user_name ?? "?")
                                    }
                                    .frame(width: 28, height: 28)
                                    .clipShape(Circle())
                                } else {
                                    initialsCircle(person.user_name ?? "?")
                                }
                                // ステータスランプ
                                statusLamp(person.status)
                            }
                            .contentShape(Circle())
                            .onTapGesture {
                                if let x = person.estimated_x, let y = person.estimated_y {
                                    highlightTarget = HighlightTarget(
                                        beaconId: person.beacon_id,
                                        userName: person.user_name,
                                        x: x, y: y
                                    )
                                }
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text(person.user_name ?? person.beacon_id.prefix(8).description)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(AppTheme.textPrimary)
                                if let dept = person.department, let job = person.job_title {
                                    Text("\(dept) / \(job)")
                                        .font(.caption2)
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                            }

                            Spacer()

                            statusBadge(person.status)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var floorPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(hex: "#303060"))
            .frame(height: 200)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "map")
                        .font(.largeTitle)
                        .foregroundColor(AppTheme.textSecondary)
                    Text("フロアプラン未設定")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                }
            )
    }

    private func initialsCircle(_ name: String) -> some View {
        Circle()
            .fill(AppTheme.accentPurple.opacity(0.3))
            .frame(width: 28, height: 28)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundColor(AppTheme.textPrimary)
            )
    }

    private func statusBadge(_ status: String?) -> some View {
        let (text, color): (String, Color) = statusInfo(status)
        return Text(text)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }

    private func statusLamp(_ status: String?) -> some View {
        let (_, color) = statusInfo(status)
        return Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(AppTheme.cardBackground, lineWidth: 1.5))
            .shadow(color: color.opacity(0.6), radius: 2)
    }

    private func statusInfo(_ status: String?) -> (String, Color) {
        switch status {
        case "available": return ("取込可", .green)
        case "busy":      return ("取込中", .red)
        case "meeting":   return ("会議中", .orange)
        case "break":     return ("休憩中", .blue)
        default:          return ("--", .gray)
        }
    }
}

// MARK: - お好み選択
struct PreferenceSection: View {
    @Binding var prefTemp: String
    @Binding var prefOccupancy: String
    @Binding var prefLight: String
    @Binding var prefHumidity: String
    @Binding var prefCo2: String
    var onUpdate: () -> Void

    var body: some View {
        DashboardCard(title: "お好み選択") {
            VStack(spacing: 4) {
                prefRow(label: "温度", selection: $prefTemp, options: [
                    ("any", "指定なし"), ("cool", "涼しい"), ("warm", "暖かい")
                ])
                prefRow(label: "混雑", selection: $prefOccupancy, options: [
                    ("any", "指定なし"), ("quiet", "空いている"), ("busy", "賑やか")
                ])
                prefRow(label: "明るさ", selection: $prefLight, options: [
                    ("any", "指定なし"), ("bright", "明るい"), ("dark", "暗め")
                ])
                prefRow(label: "湿度", selection: $prefHumidity, options: [
                    ("any", "指定なし"), ("dry", "乾燥"), ("humid", "多湿")
                ])
                prefRow(label: "CO2", selection: $prefCo2, options: [
                    ("any", "指定なし"), ("fresh", "新鮮"), ("stuffy", "換気不足")
                ])
            }
        }
        .onChange(of: prefTemp) { onUpdate() }
        .onChange(of: prefOccupancy) { onUpdate() }
        .onChange(of: prefLight) { onUpdate() }
        .onChange(of: prefHumidity) { onUpdate() }
        .onChange(of: prefCo2) { onUpdate() }
    }

    private func prefRow(label: String, selection: Binding<String>, options: [(String, String)]) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 32, alignment: .leading)
            Picker(label, selection: selection) {
                ForEach(options, id: \.0) { opt in
                    Text(opt.1).tag(opt.0)
                }
            }
            .pickerStyle(.menu)
            .tint(AppTheme.textPrimary)
            .scaleEffect(0.85, anchor: .leading)
        }
        .frame(height: 28)
    }
}

// MARK: - 折れ線グラフ
struct LineChartSection: View {
    @ObservedObject var apiService: APIService
    @Binding var sensor: SensorType

    var body: some View {
        DashboardCard(title: "時系列トレンド") {
            SensorMiniTabs(selected: $sensor)

            if apiService.lineChartData.isEmpty || apiService.lineChartData.allSatisfy({ $0.isEmpty }) {
                Text("データ蓄積中...")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(height: 180)
            } else {
                Chart {
                    ForEach(Array(apiService.sensorData.enumerated()), id: \.offset) { index, reading in
                        let piName = reading.id
                        if index < apiService.lineChartData.count {
                            ForEach(apiService.lineChartData[index].indices.suffix(20), id: \.self) { i in
                                let point = apiService.lineChartData[index][i]
                                LineMark(
                                    x: .value("時刻", point.time),
                                    y: .value(sensor.label, point.value(for: sensor))
                                )
                                .foregroundStyle(by: .value("Pi", piName))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .font(.system(size: 8))
                                    .rotationEffect(.degrees(-45))
                            }
                        }
                    }
                }
                .chartYAxisLabel(sensor.unit)
                .chartForegroundStyleScale(range: graphColors(count: apiService.sensorData.count))
                .chartLegend(.hidden)
                .frame(height: 180)
                .padding(.bottom, 8)
            }
        }
    }

    private func graphColors(count: Int) -> [Color] {
        (0..<count).map { i in
            Color(hue: Double(i * 40).truncatingRemainder(dividingBy: 360) / 360, saturation: 0.7, brightness: 0.9)
        }
    }
}

// MARK: - 棒グラフ
struct BarChartSection: View {
    let data: [SensorReading]
    @Binding var sensor: SensorType

    var body: some View {
        DashboardCard(title: "拠点別 比較") {
            SensorMiniTabs(selected: $sensor)

            if data.isEmpty {
                Text("データなし").font(.caption).foregroundColor(AppTheme.textSecondary).frame(height: 150)
            } else {
                Chart(data) { reading in
                    BarMark(
                        x: .value("拠点", reading.id),
                        y: .value(sensor.label, reading.value(for: sensor))
                    )
                    .foregroundStyle(AppTheme.accent)
                    .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .font(.system(size: 8))
                                    .rotationEffect(.degrees(-45))
                            }
                        }
                    }
                }
                .chartYAxisLabel(sensor.unit)
                .frame(height: 150)
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - 全体平均ゲージ
struct AverageGaugeSection: View {
    @ObservedObject var apiService: APIService
    @Binding var sensor: SensorType

    var body: some View {
        DashboardCard(title: "拠点全体の平均") {
            SensorMiniTabs(selected: $sensor)

            let avg = apiService.average(for: sensor)
            let fraction = min(avg / sensor.gaugeMax, 1.0)

            VStack(spacing: 8) {
                // 半円ゲージ
                ZStack {
                    SemiCircle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 16)
                    SemiCircle()
                        .trim(from: 0, to: fraction)
                        .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .animation(.easeInOut(duration: 0.5), value: fraction)

                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", avg))
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(sensor.unit)
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .offset(y: 10)
                }
                .frame(width: 160, height: 90)

                // アラート
                alertView(for: sensor, avg: avg)
            }
        }
    }

    private func alertView(for sensor: SensorType, avg: Double) -> some View {
        let t = apiService.appConfig?.ALERT_THRESHOLDS
        // Webアプリと同じデフォルト閾値 (config.js)
        let tempLow = t?.temp_low ?? 23.0
        let tempHigh = t?.temp_high ?? 25.0
        let humLow = t?.humidity_low ?? 30.0
        let humHigh = t?.humidity_high ?? 70.0
        let luxLow = t?.lux_low ?? 200.0
        let luxHigh = t?.lux_high ?? 600.0
        let co2High = t?.co2_high ?? 400.0
        var alerts: [String] = []

        switch sensor {
        case .temp:
            if avg <= tempLow { alerts.append("部屋を温めてください！") }
            if avg >= tempHigh { alerts.append("部屋を冷やしてください！") }
        case .humidity:
            if avg <= humLow { alerts.append("加湿してください！") }
            if avg >= humHigh { alerts.append("除湿してください！") }
        case .lux:
            if avg <= luxLow { alerts.append("照明を強めてください！") }
            if avg >= luxHigh { alerts.append("照明を弱めてください！") }
        case .co2:
            if avg >= co2High { alerts.append("換気をしましょう！") }
        }

        return Group {
            if alerts.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("現在の環境は快適です").font(.caption).foregroundColor(.green)
                }
            } else {
                ForEach(alerts, id: \.self) { alert in
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text(alert).font(.caption).foregroundColor(.orange)
                    }
                }
            }
        }
    }
}

// MARK: - ユーザー検索
struct UserSearchSection: View {
    @ObservedObject var apiService: APIService
    @Binding var highlightTarget: HighlightTarget?
    @State private var query = ""
    @State private var filterDept = ""
    @State private var filterJob = ""
    @State private var sortBy = "name"
    @State private var expandedId: String?
    @State private var profileSheetTarget: UserProfile? = nil

    var body: some View {
        DashboardCard(title: "ユーザー検索") {
            // 検索入力
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppTheme.textSecondary)
                TextField("名前・スキル・職種...", text: $query)
                    .font(.subheadline)
                    .foregroundColor(AppTheme.textPrimary)
                    .autocorrectionDisabled()
                    .onChange(of: query) { doSearch() }
                if !query.isEmpty {
                    Button(action: { query = ""; apiService.searchResults = [] }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
            }
            .padding(10)
            .background(Color.black.opacity(0.2))
            .cornerRadius(8)

            // フィルタ・ソート
            HStack(spacing: 8) {
                Menu {
                    Button("すべて") { filterDept = ""; doSearch() }
                    ForEach(uniqueDepts, id: \.self) { d in
                        Button(d) { filterDept = d; doSearch() }
                    }
                } label: {
                    filterLabel("部署", value: filterDept)
                }

                Menu {
                    Button("すべて") { filterJob = ""; doSearch() }
                    ForEach(uniqueJobs, id: \.self) { j in
                        Button(j) { filterJob = j; doSearch() }
                    }
                } label: {
                    filterLabel("職種", value: filterJob)
                }

                Spacer()

                Menu {
                    Button("名前 A\u{2192}Z") { sortBy = "name"; doSearch() }
                    Button("名前 Z\u{2192}A") { sortBy = "name_desc"; doSearch() }
                    Button("部署別")    { sortBy = "department"; doSearch() }
                    Button("更新日順")  { sortBy = "updated"; doSearch() }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text("並替")
                    }
                    .font(.caption2)
                    .foregroundColor(AppTheme.textSecondary)
                }
            }
            .padding(.top, 4)

            // 検索結果
            if !apiService.searchResults.isEmpty {
                VStack(spacing: 0) {
                    Text("\(apiService.searchResults.count)件")
                        .font(.caption2)
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)

                    ForEach(apiService.searchResults) { profile in
                        VStack(spacing: 0) {
                            searchResultRow(profile)
                                .onTapGesture {
                                    expandedId = expandedId == profile.beacon_id ? nil : profile.beacon_id
                                }

                            if expandedId == profile.beacon_id {
                                profileDetail(profile)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            Task { await apiService.fetchAllProfiles() }
        }
        .sheet(item: $profileSheetTarget) { profile in
            NavigationView {
                ScrollView {
                    VStack(spacing: 16) {
                        // アバター
                        Circle()
                            .fill(AppTheme.accentPurple.opacity(0.3))
                            .frame(width: 80, height: 80)
                            .overlay(
                                Text(String((profile.user_name ?? "?").prefix(1)).uppercased())
                                    .font(.title.weight(.bold))
                                    .foregroundColor(AppTheme.textPrimary)
                            )
                            .padding(.top, 16)

                        Text(profile.user_name ?? profile.beacon_id.prefix(8).description)
                            .font(.title3.weight(.bold))
                            .foregroundColor(AppTheme.textPrimary)

                        if let dept = profile.department, !dept.isEmpty {
                            Text(dept)
                                .font(.subheadline)
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        if let job = profile.job_title, !job.isEmpty {
                            Text(job)
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary)
                        }

                        // 位置情報なし表示
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.slash")
                                .foregroundColor(.orange)
                            Text("現在の位置情報がありません")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)

                        // 詳細情報
                        VStack(alignment: .leading, spacing: 8) {
                            if let s = profile.skills, !s.isEmpty { profileRow("スキル", s) }
                            if let pr = profile.projects, !pr.isEmpty { profileRow("PJ経験", pr) }
                            if let h = profile.hobbies, !h.isEmpty { profileRow("趣味", h) }
                            if let e = profile.email, !e.isEmpty { profileRow("メール", e) }
                            if let ph = profile.phone, !ph.isEmpty { profileRow("電話", ph) }
                        }
                        .padding(16)
                        .background(AppTheme.cardBackground)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal, 16)
                }
                .background(AppTheme.background)
                .navigationTitle("プロフィール")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { profileSheetTarget = nil }
                    }
                }
            }
        }
    }

    private func profileRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 50, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundColor(AppTheme.textPrimary)
        }
    }

    private var uniqueDepts: [String] {
        Array(Set(apiService.profiles.compactMap(\.department).filter { !$0.isEmpty })).sorted()
    }
    private var uniqueJobs: [String] {
        Array(Set(apiService.profiles.compactMap(\.job_title).filter { !$0.isEmpty })).sorted()
    }

    private func doSearch() {
        Task {
            await apiService.searchUsers(
                query: query, department: filterDept.isEmpty ? nil : filterDept,
                jobTitle: filterJob.isEmpty ? nil : filterJob, sort: sortBy
            )
        }
    }

    private func filterLabel(_ label: String, value: String) -> some View {
        HStack(spacing: 2) {
            Text(value.isEmpty ? label : value)
            Image(systemName: "chevron.down")
        }
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(hex: "#40407a"))
        .foregroundColor(value.isEmpty ? AppTheme.textSecondary : AppTheme.accent)
        .cornerRadius(6)
    }

    private func searchResultRow(_ p: UserProfile) -> some View {
        let personPos = apiService.persons.first { $0.beacon_id == p.beacon_id }
        let hasPosition = personPos?.estimated_x != nil && personPos?.estimated_y != nil

        return HStack(spacing: 10) {
                Circle()
                    .fill(AppTheme.accentPurple.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(String((p.user_name ?? "?").prefix(1)).uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundColor(AppTheme.textPrimary)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // アイコンタップ: 位置あり→ヒートマップでパルス表示 / 位置なし→プロフィール表示
                        if hasPosition {
                            highlightTarget = HighlightTarget(
                                beaconId: p.beacon_id,
                                userName: p.user_name,
                                x: personPos?.estimated_x,
                                y: personPos?.estimated_y
                            )
                        } else {
                            profileSheetTarget = p
                        }
                    }

            VStack(alignment: .leading, spacing: 2) {
                Text(p.user_name ?? p.beacon_id.prefix(8).description)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Text([p.department, p.job_title].compactMap { $0 }.joined(separator: " / "))
                    .font(.caption2)
                    .foregroundColor(AppTheme.textSecondary)
            }
            Spacer()

            // 位置/プロフィールアイコン
            Image(systemName: hasPosition ? "mappin.circle.fill" : "person.crop.circle")
                .font(.system(size: 18))
                .foregroundColor(hasPosition ? AppTheme.accent : AppTheme.textSecondary)
                .onTapGesture {
                    if hasPosition {
                        highlightTarget = HighlightTarget(
                            beaconId: p.beacon_id,
                            userName: p.user_name,
                            x: personPos?.estimated_x,
                            y: personPos?.estimated_y
                        )
                    } else {
                        profileSheetTarget = p
                    }
                }

            Image(systemName: expandedId == p.beacon_id ? "chevron.up" : "chevron.down")
                .font(.caption2)
                .foregroundColor(AppTheme.textSecondary)
        }
        .padding(.vertical, 8)
    }

    private func profileDetail(_ p: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let s = p.skills, !s.isEmpty { detailRow("スキル", s) }
            if let pr = p.projects, !pr.isEmpty { detailRow("PJ経験", pr) }
            if let h = p.hobbies, !h.isEmpty { detailRow("趣味", h) }
            if let e = p.email, !e.isEmpty { detailRow("メール", e) }
            if let ph = p.phone, !ph.isEmpty { detailRow("電話", ph) }
        }
        .padding(12)
        .background(AppTheme.background)
        .cornerRadius(8)
        .padding(.bottom, 6)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 50, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundColor(AppTheme.textPrimary)
        }
    }
}

// MARK: - 共通コンポーネント

struct DashboardCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundColor(AppTheme.textPrimary)
            content
        }
        .padding(14)
        .background(AppTheme.cardBackground)
        .cornerRadius(10)
    }
}

struct SensorMiniTabs: View {
    @Binding var selected: SensorType

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(SensorType.allCases) { s in
                    Button(s.label) { selected = s }
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(selected == s ? AppTheme.accent : Color(hex: "#40407a"))
                        .foregroundColor(selected == s ? Color(hex: "#1a1a2e") : AppTheme.textPrimary)
                        .cornerRadius(4)
                        .fixedSize()
                }
            }
        }
    }
}

struct SemiCircle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY),
            radius: min(rect.width, rect.height * 2) / 2,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        return path
    }
}

// MARK: - Color Hex 拡張
extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
