//
//  AdminView.swift
//  tohata_ios_02
//
//  管理者設定画面 (Webアプリの設定モーダルに相当)
//

import SwiftUI
import PhotosUI

// MARK: - 管理者タブ
struct AdminTab: View {
    @ObservedObject var apiService: APIService

    @State private var isAuthenticated = false
    @State private var password = ""
    @State private var authError = ""
    @State private var isAuthenticating = false

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(title: "管理者設定")

            if isAuthenticated {
                AdminPanelView(apiService: apiService)
            } else {
                authView
            }
        }
        .background(AppTheme.background)
    }

    private var authView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundColor(AppTheme.accent)

            Text("管理者認証")
                .font(.title3.weight(.bold))
                .foregroundColor(AppTheme.textPrimary)

            Text("設定画面にアクセスするには\nパスワードを入力してください。")
                .font(.subheadline)
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                SecureField("パスワード", text: $password)
                    .font(.body)
                    .padding(12)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(10)
                    .foregroundColor(AppTheme.textPrimary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(authError.isEmpty ? Color.clear : Color.red.opacity(0.5), lineWidth: 1)
                    )

                if !authError.isEmpty {
                    Text(authError)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Button(action: authenticate) {
                    HStack {
                        if isAuthenticating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text("認証")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(AppTheme.accent)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(password.isEmpty || isAuthenticating)
            }
            .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
        .padding(.bottom, 100)
    }

    private func authenticate() {
        isAuthenticating = true
        authError = ""
        Task {
            let success = await apiService.verifyAdminPassword(password)
            isAuthenticating = false
            if success {
                isAuthenticated = true
            } else {
                authError = "パスワードが正しくありません。"
                password = ""
            }
        }
    }
}

// MARK: - 管理者パネル (タブ切替)
enum AdminSection: String, CaseIterable, Identifiable {
    case floorplan    = "フロアプラン"
    case calibration  = "キャリブレーション"
    case beacons      = "ビーコン配置"
    case boundary     = "フロア外枠"
    case floorObjects = "オブジェクト"
    case furniture    = "椅子/廊下"
    case users        = "ユーザー管理"
    case config       = "設定情報"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .floorplan:    return "map"
        case .calibration:  return "scope"
        case .beacons:      return "sensor.tag.radiowaves.forward"
        case .boundary:     return "square.dashed"
        case .floorObjects: return "cube"
        case .furniture:    return "chair.lounge"
        case .users:        return "person.2"
        case .config:       return "gearshape"
        }
    }
}

struct AdminPanelView: View {
    @ObservedObject var apiService: APIService
    @State private var selectedSection: AdminSection = .floorplan

    var body: some View {
        VStack(spacing: 0) {
            // セクションタブ
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(AdminSection.allCases) { section in
                        Button(action: { selectedSection = section }) {
                            HStack(spacing: 4) {
                                Image(systemName: section.icon)
                                    .font(.caption2)
                                Text(section.rawValue)
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(selectedSection == section ? AppTheme.accent : Color(hex: "#40407a"))
                            .foregroundColor(selectedSection == section ? Color(hex: "#1a1a2e") : AppTheme.textPrimary)
                            .cornerRadius(4)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(AppTheme.background.opacity(0.9))

            ScrollView {
                VStack(spacing: 14) {
                    // サーバー同期ステータス
                    syncStatusBar

                    switch selectedSection {
                    case .floorplan:
                        FloorplanAdminSection(apiService: apiService)
                    case .calibration:
                        CalibrationAdminSection(apiService: apiService)
                    case .beacons:
                        BeaconPlacementSection(apiService: apiService)
                    case .boundary:
                        FloorBoundarySection(apiService: apiService)
                    case .floorObjects:
                        FloorObjectSection(apiService: apiService)
                    case .furniture:
                        FurnitureSection(apiService: apiService)
                    case .users:
                        UserManagementSection(apiService: apiService)
                    case .config:
                        ConfigInfoSection(apiService: apiService)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
        }
        .task {
            // パネル表示時にサーバーから最新設定を取得（完了を待つ）
            await apiService.fetchConfigAsync()
        }
    }

    private var syncStatusBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(apiService.appConfig != nil ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(apiService.appConfig != nil ? "サーバーと同期済み" : "サーバー未接続")
                .font(.caption2)
                .foregroundColor(apiService.appConfig != nil ? Color.green : Color.orange)
            Spacer()
            Button(action: { apiService.fetchConfig() }) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise")
                    Text("再読込")
                }
                .font(.caption2.weight(.medium))
                .foregroundColor(AppTheme.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.2))
        .cornerRadius(6)
    }
}

// MARK: - フロアプランアップロード
struct FloorplanAdminSection: View {
    @ObservedObject var apiService: APIService
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil
    @State private var isUploading = false
    @State private var uploadMessage = ""

    var body: some View {
        DashboardCard(title: "フロアプラン画像") {
            // 現在のフロアプラン
            VStack(spacing: 12) {
                Text("現在の設定")
                    .font(.caption.weight(.bold))
                    .foregroundColor(AppTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let url = apiService.floorplanURL() {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                                .cornerRadius(8)
                        case .failure:
                            Text("画像読込に失敗").font(.caption).foregroundColor(.red)
                        default:
                            ProgressView().tint(AppTheme.accent)
                        }
                    }
                    .frame(maxHeight: 200)
                } else {
                    Text("フロアプラン未設定")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                        .background(Color.black.opacity(0.15))
                        .cornerRadius(8)
                }

                Divider().background(Color.white.opacity(0.1))

                // アップロード
                Text("新しい画像をアップロード")
                    .font(.caption.weight(.bold))
                    .foregroundColor(AppTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let data = selectedImageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 150)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppTheme.accent, lineWidth: 1)
                        )
                }

                HStack(spacing: 12) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            Text("画像を選択")
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(hex: "#40407a"))
                        .foregroundColor(AppTheme.textPrimary)
                        .cornerRadius(8)
                    }

                    if selectedImageData != nil {
                        Button(action: uploadFloorplan) {
                            HStack {
                                if isUploading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.7)
                                }
                                Image(systemName: "arrow.up.circle")
                                Text("アップロード")
                            }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(AppTheme.accent)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .disabled(isUploading)
                    }
                }

                if !uploadMessage.isEmpty {
                    Text(uploadMessage)
                        .font(.caption)
                        .foregroundColor(uploadMessage.contains("成功") ? .green : .red)
                }
            }
        }
        .onChange(of: selectedPhoto) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    selectedImageData = data
                }
            }
        }

        // フロアプラン寸法情報
        if let fp = apiService.appConfig?.FLOORPLAN_IMAGE {
            DashboardCard(title: "画像情報") {
                VStack(alignment: .leading, spacing: 6) {
                    infoRow("URL", fp.url ?? "未設定")
                    infoRow("幅", fp.width != nil ? "\(Int(fp.width!)) px" : "未設定")
                    infoRow("高さ", fp.height != nil ? "\(Int(fp.height!)) px" : "未設定")
                }
            }
        }
    }

    private func uploadFloorplan() {
        guard let data = selectedImageData else { return }
        isUploading = true
        uploadMessage = ""
        Task {
            let success = await apiService.uploadFloorplan(imageData: data, filename: "floorplan.png")
            isUploading = false
            uploadMessage = success ? "アップロード成功" : "アップロードに失敗しました"
            if success {
                selectedImageData = nil
                selectedPhoto = nil
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundColor(AppTheme.textPrimary)
        }
    }
}

// MARK: - ユーザー管理
struct UserManagementSection: View {
    @ObservedObject var apiService: APIService
    @State private var editingProfile: UserProfile?
    @State private var isEditing = false

    // フォームフィールド
    @State private var editName = ""
    @State private var editJob = ""
    @State private var editDept = ""
    @State private var editSkills = ""
    @State private var editHobbies = ""
    @State private var editEmail = ""
    @State private var editPhone = ""
    @State private var editPhoto: PhotosPickerItem? = nil
    @State private var editPhotoData: Data? = nil
    @State private var isSaving = false
    @State private var saveMessage = ""
    @State private var deleteTarget: UserProfile? = nil

    var body: some View {
        Group {
        // ユーザー一覧
        DashboardCard(title: "登録ユーザー一覧") {
            if apiService.profiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.slash")
                        .font(.title2)
                        .foregroundColor(AppTheme.textSecondary)
                    Text("登録ユーザーがいません")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(apiService.profiles) { profile in
                        Button(action: { startEditing(profile) }) {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(AppTheme.accentPurple.opacity(0.3))
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Text(String((profile.user_name ?? "?").prefix(1)).uppercased())
                                            .font(.caption.weight(.bold))
                                            .foregroundColor(AppTheme.textPrimary)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.user_name ?? profile.beacon_id)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(AppTheme.textPrimary)
                                    Text([profile.department, profile.job_title].compactMap { $0 }.joined(separator: " / "))
                                        .font(.caption2)
                                        .foregroundColor(AppTheme.textSecondary)
                                }

                                Spacer()

                                Button(action: { deleteTarget = profile }) {
                                    Image(systemName: "trash.circle")
                                        .foregroundColor(.red.opacity(0.7))
                                }

                                Image(systemName: "pencil.circle")
                                    .foregroundColor(AppTheme.accent)
                            }
                            .padding(.vertical, 8)
                        }

                        if profile.id != apiService.profiles.last?.id {
                            Divider().background(Color.white.opacity(0.08))
                        }
                    }
                }
            }

            Button(action: {
                Task { await apiService.fetchAllProfiles() }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("リストを更新")
                }
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(hex: "#40407a"))
                .foregroundColor(AppTheme.textPrimary)
                .cornerRadius(8)
            }
            .padding(.top, 4)
        }
        .onAppear {
            Task { await apiService.fetchAllProfiles() }
        }

        // 編集フォーム
        if isEditing, let profile = editingProfile {
            DashboardCard(title: "プロフィール編集: \(profile.user_name ?? profile.beacon_id)") {
                VStack(alignment: .leading, spacing: 14) {
                    // アバター
                    HStack {
                        if let data = editPhotoData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(AppTheme.accent, lineWidth: 2))
                        } else {
                            Circle()
                                .fill(AppTheme.accentPurple.opacity(0.3))
                                .frame(width: 56, height: 56)
                                .overlay(
                                    Text(String(editName.prefix(1)).uppercased())
                                        .font(.title3.weight(.bold))
                                        .foregroundColor(AppTheme.textPrimary)
                                )
                                .overlay(Circle().stroke(AppTheme.accent, lineWidth: 2))
                        }

                        PhotosPicker(selection: $editPhoto, matching: .images) {
                            Text("画像を変更")
                                .font(.caption)
                                .foregroundColor(AppTheme.accent)
                        }
                    }

                    adminField("ビーコンID", value: profile.beacon_id, editable: false)
                    adminEditField("名前", text: $editName)
                    adminEditField("職種", text: $editJob)
                    adminEditField("部署", text: $editDept)
                    adminEditField("スキル", text: $editSkills, placeholder: "Python, React, CAD")
                    adminEditField("趣味", text: $editHobbies, placeholder: "ランニング, 読書")
                    adminEditField("メール", text: $editEmail, keyboard: .emailAddress)
                    adminEditField("電話", text: $editPhone, keyboard: .phonePad)

                    HStack(spacing: 12) {
                        Button(action: { isEditing = false }) {
                            Text("キャンセル")
                                .font(.caption.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(hex: "#40407a"))
                                .foregroundColor(AppTheme.textPrimary)
                                .cornerRadius(8)
                        }

                        Button(action: saveProfile) {
                            HStack {
                                if isSaving {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.7)
                                }
                                Text("保存")
                            }
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(AppTheme.accent)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .disabled(isSaving)
                    }

                    if !saveMessage.isEmpty {
                        Text(saveMessage)
                            .font(.caption)
                            .foregroundColor(saveMessage.contains("成功") ? .green : .red)
                    }
                }
            }
            .onChange(of: editPhoto) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        editPhotoData = data
                    }
                }
            }
        }
        } // Group
        .alert("ユーザー削除", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("削除", role: .destructive) {
                if let target = deleteTarget {
                    Task {
                        let success = await apiService.deleteUserProfile(beaconId: target.beacon_id)
                        if success { await apiService.fetchAllProfiles() }
                    }
                }
                deleteTarget = nil
            }
            Button("キャンセル", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("\(deleteTarget?.user_name ?? deleteTarget?.beacon_id ?? "")を削除しますか？")
        }
    }

    private func startEditing(_ profile: UserProfile) {
        editingProfile = profile
        editName = profile.user_name ?? ""
        editJob = profile.job_title ?? ""
        editDept = profile.department ?? ""
        editSkills = profile.skills ?? ""
        editHobbies = profile.hobbies ?? ""
        editEmail = profile.email ?? ""
        editPhone = profile.phone ?? ""
        editPhotoData = nil
        editPhoto = nil
        saveMessage = ""
        isEditing = true
    }

    private func saveProfile() {
        guard let profile = editingProfile else { return }
        isSaving = true
        saveMessage = ""

        Task {
            // 画像アップロード
            if let data = editPhotoData,
               let compressed = UIImage(data: data)?.jpegData(compressionQuality: 0.7) {
                _ = await apiService.uploadProfileImage(beaconId: profile.beacon_id, imageData: compressed)
            }

            // プロフィール更新
            let updated = UserProfile(
                beacon_id: profile.beacon_id,
                user_name: editName.isEmpty ? nil : editName,
                job_title: editJob.isEmpty ? nil : editJob,
                department: editDept.isEmpty ? nil : editDept,
                skills: editSkills.isEmpty ? nil : editSkills,
                hobbies: editHobbies.isEmpty ? nil : editHobbies,
                projects: profile.projects,
                email: editEmail.isEmpty ? nil : editEmail,
                phone: editPhone.isEmpty ? nil : editPhone,
                profile_image: profile.profile_image
            )
            let success = await apiService.updateUserProfile(updated)
            isSaving = false
            saveMessage = success ? "保存に成功しました" : "保存に失敗しました"
            if success {
                await apiService.fetchAllProfiles()
            }
        }
    }

    private func adminField(_ label: String, value: String, editable: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundColor(editable ? AppTheme.textPrimary : AppTheme.textSecondary.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func adminEditField(_ label: String, text: Binding<String>, placeholder: String = "", keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 70, alignment: .leading)
            TextField(placeholder.isEmpty ? label : placeholder, text: text)
                .font(.caption)
                .foregroundColor(AppTheme.textPrimary)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .padding(6)
                .background(Color.black.opacity(0.2))
                .cornerRadius(6)
        }
    }
}

// MARK: - キャリブレーション設定
struct CalibrationAdminSection: View {
    @ObservedObject var apiService: APIService
    @State private var originX = ""
    @State private var originY = ""
    @State private var scaleMmPerPx = ""
    @State private var isSaving = false
    @State private var message = ""

    var body: some View {
        // 現在の値表示
        DashboardCard(title: "現在のキャリブレーション") {
            VStack(alignment: .leading, spacing: 6) {
                if let cal = apiService.appConfig?.CALIBRATION {
                    if let origin = cal.origin_px {
                        calInfoRow("原点 X (px)", String(format: "%.2f", origin.x))
                        calInfoRow("原点 Y (px)", String(format: "%.2f", origin.y))
                    } else {
                        calInfoRow("原点", "未設定")
                    }
                    calInfoRow("縮尺 (mm/px)", cal.scale_mm_per_px != nil ? String(format: "%.3f", cal.scale_mm_per_px!) : "未設定")
                } else {
                    Text("キャリブレーション未設定")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
        }

        // フロアプランプレビュー (原点マーカー付き)
        if let url = apiService.floorplanURL() {
            let calImgW = apiService.appConfig?.FLOORPLAN_IMAGE?.width ?? 1483
            let calImgH = apiService.appConfig?.FLOORPLAN_IMAGE?.height ?? 1753
            let calAspect = calImgW / calImgH

            DashboardCard(title: "プレビュー") {
                ZStack(alignment: .topLeading) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable()
                        default:
                            Color.black.opacity(0.15)
                        }
                    }

                    // 原点マーカー
                    if let cal = apiService.appConfig?.CALIBRATION,
                       let origin = cal.origin_px,
                       calImgW > 0, calImgH > 0 {
                        GeometryReader { geo in
                            let scaleX = geo.size.width / calImgW
                            let scaleY = geo.size.height / calImgH
                            let px = origin.x * scaleX
                            // Leaflet Y-up → SwiftUI Y-down: imageY = imgH - originY
                            let py = (calImgH - origin.y) * scaleY
                            Circle()
                                .fill(Color.red)
                                .frame(width: 10, height: 10)
                                .position(x: px, y: py)
                            Text("原点")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.red)
                                .position(x: px + 18, y: py - 8)
                        }
                    }
                }
                .aspectRatio(calAspect, contentMode: .fit)
                .cornerRadius(8)
            }
        }

        // 編集フォーム
        DashboardCard(title: "キャリブレーション編集") {
            VStack(alignment: .leading, spacing: 12) {
                Text("原点座標とスケールを数値で入力してください。\nWebアプリではマップクリックで設定できます。")
                    .font(.caption2)
                    .foregroundColor(AppTheme.textSecondary)

                calEditField("原点 X (px)", text: $originX, placeholder: "116.25")
                calEditField("原点 Y (px)", text: $originY, placeholder: "340.75")
                calEditField("縮尺 (mm/px)", text: $scaleMmPerPx, placeholder: "6.335")

                Button(action: saveCalibration) {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.7)
                        }
                        Text("保存")
                    }
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(AppTheme.accent)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(isSaving || originX.isEmpty || originY.isEmpty || scaleMmPerPx.isEmpty)

                if !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(message.contains("成功") ? .green : .red)
                }
            }
        }
        .onAppear { loadCurrentValues() }
        .onChange(of: apiService.appConfig?.CALIBRATION?.scale_mm_per_px) { loadCurrentValues() }
    }

    private func loadCurrentValues() {
        if let cal = apiService.appConfig?.CALIBRATION {
            if let origin = cal.origin_px {
                originX = String(format: "%.2f", origin.x)
                originY = String(format: "%.2f", origin.y)
            }
            if let scale = cal.scale_mm_per_px {
                scaleMmPerPx = String(format: "%.3f", scale)
            }
        }
    }

    private func saveCalibration() {
        guard let ox = Double(originX), let oy = Double(originY), let sc = Double(scaleMmPerPx)
        else { message = "数値を正しく入力してください"; return }
        isSaving = true
        message = ""
        Task {
            let success = await apiService.updateCalibration(originX: ox, originY: oy, scale: sc)
            isSaving = false
            message = success ? "保存に成功しました" : "保存に失敗しました"
        }
    }

    private func calInfoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundColor(AppTheme.textPrimary)
        }
    }

    private func calEditField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 90, alignment: .leading)
            TextField(placeholder, text: text)
                .font(.caption)
                .foregroundColor(AppTheme.textPrimary)
                .keyboardType(.decimalPad)
                .autocorrectionDisabled()
                .padding(6)
                .background(Color.black.opacity(0.2))
                .cornerRadius(6)
        }
    }
}

// MARK: - ビーコン配置
struct BeaconPlacementSection: View {
    @ObservedObject var apiService: APIService

    // ビーコン一覧編集用
    @State private var beaconEntries: [BeaconEntry] = []
    @State private var isSaving = false
    @State private var message = ""
    @State private var isDrawing = false

    struct BeaconEntry: Identifiable {
        let id = UUID()
        var piId: String
        var minorId: String
        var xMm: String
        var yMm: String
    }

    var body: some View {
        // タップ配置ツールバー
        DashboardCard(title: "タップ配置") {
            VStack(spacing: 6) {
                HStack {
                    Button(action: { isDrawing.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: isDrawing ? "hand.tap.fill" : "hand.tap")
                            Text(isDrawing ? "配置 ON" : "配置 OFF")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundColor(isDrawing ? .white : AppTheme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isDrawing ? AppTheme.accent : Color.clear)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AppTheme.accent, lineWidth: 1)
                        )
                    }
                    Spacer()
                    if isDrawing {
                        Text("マップをタップしてビーコンを配置")
                            .font(.caption2)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
            }
        }

        // フロアプランプレビュー (ビーコンマーカー付き)
        if let url = apiService.floorplanURL() {
            let previewImgW = apiService.appConfig?.FLOORPLAN_IMAGE?.width ?? 1483
            let previewImgH = apiService.appConfig?.FLOORPLAN_IMAGE?.height ?? 1753
            let previewAspect = previewImgW / previewImgH

            DashboardCard(title: "ビーコン配置プレビュー") {
                beaconPreview(url: url, previewImgW: previewImgW, previewImgH: previewImgH, previewAspect: previewAspect)
            }
        }

        // ビーコン一覧
        DashboardCard(title: "ビーコン一覧 (\(beaconEntries.count)台)") {
            VStack(spacing: 0) {
                // ヘッダー
                HStack(spacing: 4) {
                    Text("Pi ID").frame(width: 55, alignment: .leading)
                    Text("Minor").frame(width: 40, alignment: .leading)
                    Text("X (mm)").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Y (mm)").frame(maxWidth: .infinity, alignment: .leading)
                    Text("").frame(width: 24)
                }
                .font(.caption2.weight(.bold))
                .foregroundColor(AppTheme.accent)
                .padding(.bottom, 6)

                ForEach($beaconEntries) { $entry in
                    HStack(spacing: 4) {
                        TextField("ras_01", text: $entry.piId)
                            .frame(width: 55)
                        TextField("1", text: $entry.minorId)
                            .frame(width: 40)
                        TextField("0", text: $entry.xMm)
                            .keyboardType(.numbersAndPunctuation)
                        TextField("0", text: $entry.yMm)
                            .keyboardType(.numbersAndPunctuation)
                        Button(action: { beaconEntries.removeAll { $0.id == entry.id } }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red.opacity(0.7))
                                .font(.caption)
                        }
                        .frame(width: 24)
                    }
                    .font(.caption)
                    .foregroundColor(AppTheme.textPrimary)
                    .padding(4)
                    .background(Color.black.opacity(0.15))
                    .cornerRadius(4)
                }

                // 追加ボタン
                Button(action: {
                    let nextId = beaconEntries.count + 1
                    beaconEntries.append(BeaconEntry(piId: "ras_\(String(format: "%02d", nextId))", minorId: "\(nextId)", xMm: "0", yMm: "0"))
                }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("ビーコンを追加")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#40407a").opacity(0.5))
                    .cornerRadius(6)
                }
                .padding(.top, 6)
            }
        }

        // 保存ボタン
        DashboardCard(title: "ビーコン設定を保存") {
            VStack(spacing: 8) {
                Text("※ 保存するとサーバーのconfigファイルが更新されます。\n反映にはサーバー再起動が必要な場合があります。")
                    .font(.caption2)
                    .foregroundColor(AppTheme.textSecondary)

                Button(action: saveBeacons) {
                    HStack {
                        if isSaving { ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(0.7) }
                        Text("ビーコン設定を保存")
                    }
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(AppTheme.accent)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(isSaving)

                if !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(message.contains("成功") ? .green : .red)
                }
            }
        }
        .onAppear { loadCurrentBeacons() }
        .onChange(of: apiService.appConfig?.BEACON_POSITIONS?.count) { loadCurrentBeacons() }
    }

    private func loadCurrentBeacons() {
        guard let positions = apiService.appConfig?.BEACON_POSITIONS else {
            // BEACON_POSITIONSがない場合、PI_LOCATIONSからフォールバック
            guard let piLocs = apiService.appConfig?.PI_LOCATIONS, !piLocs.isEmpty else { return }
            let minorMap = apiService.appConfig?.MINOR_ID_TO_PI_NAME_MAP ?? [:]
            let reverseMinor = Dictionary(minorMap.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            beaconEntries = piLocs.map { pi in
                BeaconEntry(
                    piId: pi.piId,
                    minorId: reverseMinor[pi.piId] ?? "",
                    xMm: String(Int(pi.x)),
                    yMm: String(Int(pi.y))
                )
            }
            return
        }
        let minorMap = apiService.appConfig?.MINOR_ID_TO_PI_NAME_MAP ?? [:]
        let reverseMinor = Dictionary(minorMap.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })

        beaconEntries = positions.sorted(by: { $0.key < $1.key }).map { piId, coords in
            BeaconEntry(
                piId: piId,
                minorId: reverseMinor[piId] ?? "",
                xMm: coords.count > 0 ? String(Int(coords[0])) : "0",
                yMm: coords.count > 1 ? String(Int(coords[1])) : "0"
            )
        }
    }

    private func saveBeacons() {
        isSaving = true
        message = ""

        var positions: [String: [Double]] = [:]
        var minorMap: [String: String] = [:]
        for entry in beaconEntries {
            let x = Double(entry.xMm) ?? 0
            let y = Double(entry.yMm) ?? 0
            positions[entry.piId] = [x, y]
            if !entry.minorId.isEmpty {
                minorMap[entry.minorId] = entry.piId
            }
        }

        // 既存の椅子・廊下データを保持
        let chairs = apiService.appConfig?.CHAIR_CENTERS ?? []
        let lines: [[String: Any]] = (apiService.appConfig?.CENTER_LINES ?? []).map { line in
            ["type": line.type, "coordinates": line.coordinates]
        }

        Task {
            let success = await apiService.updateBeaconConfig(
                positions: positions,
                minorIdMap: minorMap,
                chairCenters: chairs,
                centerLines: lines
            )
            isSaving = false
            message = success ? "保存に成功しました" : "保存に失敗しました"
        }
    }

    // MARK: ビーコンプレビュー（タップ配置対応）
    @ViewBuilder
    private func beaconPreview(url: URL, previewImgW: Double, previewImgH: Double, previewAspect: Double) -> some View {
        ZStack {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                default:
                    Color.black.opacity(0.15)
                }
            }

            // ビーコンマーカー表示
            GeometryReader { geo in
                // 既存ビーコンのマーカー
                ForEach(beaconEntries) { entry in
                    if let xMm = Double(entry.xMm), let yMm = Double(entry.yMm) {
                        let pt = beaconMmToView(xMm, yMm, size: geo.size)
                        VStack(spacing: 1) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                            Text(entry.piId)
                                .font(.system(size: 6, weight: .bold))
                                .foregroundColor(.orange)
                        }
                        .position(pt)
                    }
                }

                // タップ配置エリア（isDrawing時のみ）
                if isDrawing {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let mm = beaconViewToMm(location.x, location.y, in: geo.size)
                            let nextId = beaconEntries.count + 1
                            beaconEntries.append(BeaconEntry(
                                piId: "ras_\(String(format: "%02d", nextId))",
                                minorId: "\(nextId)",
                                xMm: "\(Int(mm.x))",
                                yMm: "\(Int(mm.y))"
                            ))
                        }
                }
            }
        }
        .aspectRatio(previewAspect, contentMode: .fit)
        .cornerRadius(8)
        .overlay(
            // isDrawing時は緑のボーダーを表示
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDrawing ? Color.green : Color.clear, lineWidth: 2)
        )
    }

    // MARK: 座標変換ヘルパー（mm → View座標）
    private func beaconMmToView(_ mmX: Double, _ mmY: Double, size: CGSize) -> CGPoint {
        let cal = apiService.appConfig?.CALIBRATION
        let imgW = apiService.appConfig?.FLOORPLAN_IMAGE?.width ?? 1483
        let imgH = apiService.appConfig?.FLOORPLAN_IMAGE?.height ?? 1753
        let originX = cal?.origin_px?.x ?? 116.25
        let originY = cal?.origin_px?.y ?? 340.75
        let scale = cal?.scale_mm_per_px ?? 6.335
        let pxX = mmX / scale + originX
        let pxY = imgH - (-mmY / scale + originY)
        return CGPoint(x: pxX / imgW * size.width, y: pxY / imgH * size.height)
    }

    // MARK: 座標変換ヘルパー（View座標 → mm）
    private func beaconViewToMm(_ viewX: Double, _ viewY: Double, in size: CGSize) -> CGPoint {
        let cal = apiService.appConfig?.CALIBRATION
        let imgW = apiService.appConfig?.FLOORPLAN_IMAGE?.width ?? 1483
        let imgH = apiService.appConfig?.FLOORPLAN_IMAGE?.height ?? 1753
        let originX = cal?.origin_px?.x ?? 116.25
        let originY = cal?.origin_px?.y ?? 340.75
        let scale = cal?.scale_mm_per_px ?? 6.335
        let pxX = viewX / size.width * imgW
        let pxY = viewY / size.height * imgH
        let mmX = (pxX - originX) * scale
        let mmY = -((imgH - pxY) - originY) * scale
        return CGPoint(x: round(mmX), y: round(mmY))
    }
}

// MARK: - フロア外枠
struct FloorBoundarySection: View {
    @ObservedObject var apiService: APIService
    @State private var boundaryPoints: [EditablePoint] = []
    @State private var isSaving = false
    @State private var message = ""
    @State private var isDrawing = false

    struct EditablePoint: Identifiable {
        let id = UUID()
        var xMm: String
        var yMm: String
    }

    var body: some View {
        // タップ配置ツールバー
        DashboardCard(title: "タップ配置") {
            VStack(spacing: 6) {
                HStack {
                    Button(action: { isDrawing.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: isDrawing ? "hand.tap.fill" : "hand.tap")
                            Text(isDrawing ? "配置 ON" : "配置 OFF")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundColor(isDrawing ? .white : AppTheme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isDrawing ? AppTheme.accent : Color.clear)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AppTheme.accent, lineWidth: 1)
                        )
                    }
                    Spacer()
                    if isDrawing {
                        Text("マップをタップして頂点を追加")
                            .font(.caption2)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
            }
        }

        // フロアプランプレビュー (外枠ポリゴン描画)
        if let url = apiService.floorplanURL() {
            let boundImgW = apiService.appConfig?.FLOORPLAN_IMAGE?.width ?? 1483
            let boundImgH = apiService.appConfig?.FLOORPLAN_IMAGE?.height ?? 1753
            let boundAspect = boundImgW / boundImgH

            DashboardCard(title: "フロア外枠プレビュー") {
                ZStack {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable()
                        default:
                            Color.black.opacity(0.15)
                        }
                    }

                    // ポリゴン描画 + 頂点番号マーカー + タップ配置
                    GeometryReader { geo in
                        // ポリゴン描画（3点以上の場合）
                        let points: [CGPoint] = boundaryPoints.compactMap { pt in
                            guard let xMm = Double(pt.xMm), let yMm = Double(pt.yMm) else { return nil }
                            return boundMmToView(xMm, yMm, size: geo.size)
                        }
                        if points.count >= 3 {
                            Path { path in
                                path.move(to: points[0])
                                for i in 1..<points.count { path.addLine(to: points[i]) }
                                path.closeSubpath()
                            }
                            .stroke(Color.orange, lineWidth: 2)
                            .fill(Color.orange.opacity(0.1))
                        }

                        // 各頂点に番号マーカーを表示
                        ForEach(Array(boundaryPoints.enumerated()), id: \.element.id) { index, pt in
                            if let xMm = Double(pt.xMm), let yMm = Double(pt.yMm) {
                                let viewPt = boundMmToView(xMm, yMm, size: geo.size)
                                ZStack {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 14, height: 14)
                                    Text("\(index + 1)")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .position(viewPt)
                            }
                        }

                        // タップ配置エリア（isDrawing時のみ）
                        if isDrawing {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { location in
                                    let mm = boundViewToMm(location.x, location.y, in: geo.size)
                                    boundaryPoints.append(EditablePoint(
                                        xMm: "\(Int(mm.x))",
                                        yMm: "\(Int(mm.y))"
                                    ))
                                }
                        }
                    }
                }
                .aspectRatio(boundAspect, contentMode: .fit)
                .cornerRadius(8)
                .overlay(
                    // isDrawing時は緑のボーダーを表示
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isDrawing ? Color.green : Color.clear, lineWidth: 2)
                )
            }
        }

        // 頂点リスト
        DashboardCard(title: "外枠頂点 (\(boundaryPoints.count)点)") {
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    Text("#").frame(width: 20, alignment: .leading)
                    Text("X (mm)").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Y (mm)").frame(maxWidth: .infinity, alignment: .leading)
                    Text("").frame(width: 24)
                }
                .font(.caption2.weight(.bold))
                .foregroundColor(AppTheme.accent)
                .padding(.bottom, 6)

                ForEach(Array(boundaryPoints.enumerated()), id: \.element.id) { index, _ in
                    HStack(spacing: 4) {
                        Text("\(index + 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(AppTheme.textSecondary)
                            .frame(width: 20, alignment: .leading)
                        TextField("0", text: $boundaryPoints[index].xMm)
                            .keyboardType(.numbersAndPunctuation)
                        TextField("0", text: $boundaryPoints[index].yMm)
                            .keyboardType(.numbersAndPunctuation)
                        Button(action: { boundaryPoints.remove(at: index) }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red.opacity(0.7))
                                .font(.caption)
                        }
                        .frame(width: 24)
                    }
                    .font(.caption)
                    .foregroundColor(AppTheme.textPrimary)
                    .padding(4)
                    .background(Color.black.opacity(0.15))
                    .cornerRadius(4)
                }

                Button(action: {
                    boundaryPoints.append(EditablePoint(xMm: "0", yMm: "0"))
                }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("頂点を追加")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#40407a").opacity(0.5))
                    .cornerRadius(6)
                }
                .padding(.top, 6)
            }
        }

        // 保存
        DashboardCard(title: "外枠を保存") {
            VStack(spacing: 8) {
                Text("※ 最低3点の頂点が必要です。フロア領域を囲む多角形を定義します。")
                    .font(.caption2)
                    .foregroundColor(AppTheme.textSecondary)

                Button(action: saveBoundary) {
                    HStack {
                        if isSaving { ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(0.7) }
                        Text("フロア外枠を保存")
                    }
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(boundaryPoints.count >= 3 ? AppTheme.accent : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(isSaving || boundaryPoints.count < 3)

                if !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(message.contains("成功") ? .green : .red)
                }
            }
        }
        .onAppear { loadCurrentBoundary() }
        .onChange(of: apiService.appConfig?.FLOOR_BOUNDARY?.count) { loadCurrentBoundary() }
    }

    private func loadCurrentBoundary() {
        guard let boundary = apiService.appConfig?.FLOOR_BOUNDARY else { return }
        boundaryPoints = boundary.map { EditablePoint(xMm: String(Int($0.x)), yMm: String(Int($0.y))) }
    }

    private func saveBoundary() {
        guard boundaryPoints.count >= 3 else { return }
        isSaving = true
        message = ""

        let points: [[String: Double]] = boundaryPoints.compactMap { pt in
            guard let x = Double(pt.xMm), let y = Double(pt.yMm) else { return nil }
            return ["x": x, "y": y]
        }

        Task {
            let success = await apiService.updateFloorBoundary(boundary: points)
            isSaving = false
            message = success ? "保存に成功しました" : "保存に失敗しました"
        }
    }

    // MARK: 座標変換ヘルパー（mm → View座標）
    private func boundMmToView(_ mmX: Double, _ mmY: Double, size: CGSize) -> CGPoint {
        let cal = apiService.appConfig?.CALIBRATION
        let imgW = apiService.appConfig?.FLOORPLAN_IMAGE?.width ?? 1483
        let imgH = apiService.appConfig?.FLOORPLAN_IMAGE?.height ?? 1753
        let originX = cal?.origin_px?.x ?? 116.25
        let originY = cal?.origin_px?.y ?? 340.75
        let scale = cal?.scale_mm_per_px ?? 6.335
        let pxX = mmX / scale + originX
        let pxY = imgH - (-mmY / scale + originY)
        return CGPoint(x: pxX / imgW * size.width, y: pxY / imgH * size.height)
    }

    // MARK: 座標変換ヘルパー（View座標 → mm）
    private func boundViewToMm(_ viewX: Double, _ viewY: Double, in size: CGSize) -> CGPoint {
        let cal = apiService.appConfig?.CALIBRATION
        let imgW = apiService.appConfig?.FLOORPLAN_IMAGE?.width ?? 1483
        let imgH = apiService.appConfig?.FLOORPLAN_IMAGE?.height ?? 1753
        let originX = cal?.origin_px?.x ?? 116.25
        let originY = cal?.origin_px?.y ?? 340.75
        let scale = cal?.scale_mm_per_px ?? 6.335
        let pxX = viewX / size.width * imgW
        let pxY = viewY / size.height * imgH
        let mmX = (pxX - originX) * scale
        let mmY = -((imgH - pxY) - originY) * scale
        return CGPoint(x: round(mmX), y: round(mmY))
    }
}

// MARK: - 椅子 / 廊下 (家具配置)
struct FurnitureSection: View {
    @ObservedObject var apiService: APIService
    @State private var chairEntries: [ChairEntry] = []
    @State private var lineEntries: [LineEntry] = []
    @State private var isSaving = false
    @State private var message = ""

    struct ChairEntry: Identifiable {
        let id = UUID()
        var xMm: String
        var yMm: String
    }

    struct LineEntry: Identifiable {
        let id = UUID()
        var points: [ChairEntry]  // 各点のX, Y
    }

    var body: some View {
        furniturePreview
        chairListCard
        centerLineListCard
        furnitureSaveButton
            .onAppear { loadCurrentFurniture() }
            .onChange(of: apiService.appConfig?.CHAIR_CENTERS?.count) { loadCurrentFurniture() }
    }

    // MARK: - プレビュー
    @ViewBuilder
    private var furniturePreview: some View {
        if let url = apiService.floorplanURL() {
            let furnImgW = apiService.appConfig?.FLOORPLAN_IMAGE?.width ?? 1483
            let furnImgH = apiService.appConfig?.FLOORPLAN_IMAGE?.height ?? 1753
            let furnAspect = furnImgW / furnImgH

            DashboardCard(title: "家具配置プレビュー") {
                ZStack {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable()
                        default:
                            Color.black.opacity(0.15)
                        }
                    }

                    if let cal = apiService.appConfig?.CALIBRATION,
                       let origin = cal.origin_px,
                       let scale = cal.scale_mm_per_px,
                       furnImgW > 0, furnImgH > 0, scale > 0 {
                        GeometryReader { geo in
                            let vsx = geo.size.width / furnImgW
                            let vsy = geo.size.height / furnImgH

                            // 椅子マーカー
                            ForEach(chairEntries) { entry in
                                if let x = Double(entry.xMm), let y = Double(entry.yMm) {
                                    let px = (x / scale + origin.x) * vsx
                                    // Leaflet Y-up → SwiftUI Y-down
                                    let py = (furnImgH - (-y / scale + origin.y)) * vsy
                                    Image(systemName: "chair.lounge.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(.cyan)
                                        .position(x: px, y: py)
                                }
                            }

                            // 廊下中心線
                            ForEach(lineEntries) { line in
                                let pts: [CGPoint] = line.points.compactMap { pt in
                                    guard let x = Double(pt.xMm), let y = Double(pt.yMm) else { return nil }
                                    return CGPoint(x: (x / scale + origin.x) * vsx, y: (furnImgH - (-y / scale + origin.y)) * vsy)
                                }
                                if pts.count >= 2 {
                                    Path { path in
                                        path.move(to: pts[0])
                                        for i in 1..<pts.count { path.addLine(to: pts[i]) }
                                    }
                                    .stroke(Color.green, lineWidth: 2)
                                }
                            }
                        }
                    }
                }
                .aspectRatio(furnAspect, contentMode: .fit)
                .cornerRadius(8)
            }
        }
    }

    // MARK: - 椅子一覧カード
    private var chairListCard: some View {
        DashboardCard(title: "椅子位置 (\(chairEntries.count)脚)") {
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    Text("#").frame(width: 20, alignment: .leading)
                    Text("X (mm)").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Y (mm)").frame(maxWidth: .infinity, alignment: .leading)
                    Text("").frame(width: 24)
                }
                .font(.caption2.weight(.bold))
                .foregroundColor(AppTheme.accent)
                .padding(.bottom, 4)

                ForEach(Array(chairEntries.enumerated()), id: \.element.id) { index, _ in
                    HStack(spacing: 4) {
                        Text("\(index + 1)")
                            .font(.caption2)
                            .foregroundColor(AppTheme.textSecondary)
                            .frame(width: 20, alignment: .leading)
                        TextField("0", text: $chairEntries[index].xMm)
                            .keyboardType(.numbersAndPunctuation)
                        TextField("0", text: $chairEntries[index].yMm)
                            .keyboardType(.numbersAndPunctuation)
                        Button(action: { chairEntries.remove(at: index) }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red.opacity(0.7))
                                .font(.caption)
                        }
                        .frame(width: 24)
                    }
                    .font(.caption)
                    .foregroundColor(AppTheme.textPrimary)
                    .padding(4)
                    .background(Color.black.opacity(0.15))
                    .cornerRadius(4)
                }

                Button(action: {
                    chairEntries.append(ChairEntry(xMm: "0", yMm: "0"))
                }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("椅子を追加")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#40407a").opacity(0.5))
                    .cornerRadius(6)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - 廊下中心線カード
    private var centerLineListCard: some View {
        DashboardCard(title: "廊下中心線 (\(lineEntries.count)本)") {
            VStack(spacing: 6) {
                ForEach(Array(lineEntries.enumerated()), id: \.element.id) { lineIndex, line in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("ライン \(lineIndex + 1)")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(AppTheme.accent)
                            Spacer()
                            Button(action: { lineEntries.remove(at: lineIndex) }) {
                                Image(systemName: "trash.circle")
                                    .foregroundColor(.red.opacity(0.7))
                                    .font(.caption)
                            }
                        }

                        ForEach(Array(line.points.enumerated()), id: \.element.id) { ptIndex, _ in
                            HStack(spacing: 4) {
                                Text("P\(ptIndex + 1)")
                                    .font(.caption2)
                                    .foregroundColor(AppTheme.textSecondary)
                                    .frame(width: 24, alignment: .leading)
                                TextField("X", text: $lineEntries[lineIndex].points[ptIndex].xMm)
                                    .keyboardType(.numbersAndPunctuation)
                                TextField("Y", text: $lineEntries[lineIndex].points[ptIndex].yMm)
                                    .keyboardType(.numbersAndPunctuation)
                                Button(action: { lineEntries[lineIndex].points.remove(at: ptIndex) }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red.opacity(0.7))
                                        .font(.system(size: 10))
                                }
                                .frame(width: 20)
                            }
                            .font(.caption)
                            .foregroundColor(AppTheme.textPrimary)
                            .padding(3)
                            .background(Color.black.opacity(0.1))
                            .cornerRadius(4)
                        }

                        Button(action: {
                            lineEntries[lineIndex].points.append(ChairEntry(xMm: "0", yMm: "0"))
                        }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                Text("点を追加")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.accent)
                        }
                    }
                    .padding(8)
                    .background(Color(hex: "#40407a").opacity(0.3))
                    .cornerRadius(6)
                }

                Button(action: {
                    lineEntries.append(LineEntry(points: [
                        ChairEntry(xMm: "0", yMm: "0"),
                        ChairEntry(xMm: "0", yMm: "0")
                    ]))
                }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("廊下ラインを追加")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#40407a").opacity(0.5))
                    .cornerRadius(6)
                }
            }
        }
    }

    // MARK: - 保存ボタン
    private var furnitureSaveButton: some View {
        VStack(spacing: 4) {
            Button(action: saveFurniture) {
                HStack {
                    if isSaving { ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(0.7) }
                    Text("椅子 / 廊下設定を保存")
                }
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppTheme.accent)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(isSaving)

            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundColor(message.contains("成功") ? .green : .red)
            }
        }
    }

    private func loadCurrentFurniture() {
        // 椅子
        if let chairs = apiService.appConfig?.CHAIR_CENTERS {
            chairEntries = chairs.map { coords in
                ChairEntry(
                    xMm: coords.count > 0 ? String(Int(coords[0])) : "0",
                    yMm: coords.count > 1 ? String(Int(coords[1])) : "0"
                )
            }
        }
        // 廊下
        if let lines = apiService.appConfig?.CENTER_LINES {
            lineEntries = lines.map { line in
                LineEntry(points: line.coordinates.map { coord in
                    ChairEntry(
                        xMm: coord.count > 0 ? String(Int(coord[0])) : "0",
                        yMm: coord.count > 1 ? String(Int(coord[1])) : "0"
                    )
                })
            }
        }
    }

    private func saveFurniture() {
        isSaving = true
        message = ""

        let chairs: [[Double]] = chairEntries.map { entry in
            [Double(entry.xMm) ?? 0, Double(entry.yMm) ?? 0]
        }

        let lines: [[String: Any]] = lineEntries.map { line in
            let coords: [[Double]] = line.points.map { pt in
                [Double(pt.xMm) ?? 0, Double(pt.yMm) ?? 0]
            }
            return ["type": "LineString" as Any, "coordinates": coords as Any]
        }

        // 既存のビーコン設定を保持
        let positions = apiService.appConfig?.BEACON_POSITIONS ?? [:]
        let minorMap = apiService.appConfig?.MINOR_ID_TO_PI_NAME_MAP ?? [:]

        Task {
            let success = await apiService.updateBeaconConfig(
                positions: positions,
                minorIdMap: minorMap,
                chairCenters: chairs,
                centerLines: lines
            )
            isSaving = false
            message = success ? "保存に成功しました" : "保存に失敗しました"
        }
    }
}

// MARK: - 設定情報表示
struct ConfigInfoSection: View {
    @ObservedObject var apiService: APIService

    var body: some View {
        // Pi位置情報
        if let locs = apiService.appConfig?.PI_LOCATIONS, !locs.isEmpty {
            DashboardCard(title: "Pi配置 (\(locs.count)台)") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(locs) { loc in
                        HStack {
                            Text(loc.piId)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppTheme.accent)
                                .frame(width: 40, alignment: .leading)
                            Text("x=\(Int(loc.x)), y=\(Int(loc.y))")
                                .font(.caption)
                                .foregroundColor(AppTheme.textPrimary)
                        }
                    }
                }
            }
        }

        // サーバー情報
        DashboardCard(title: "サーバー情報") {
            VStack(alignment: .leading, spacing: 6) {
                configRow("URL", ServerConfig.baseURL)
                configRow("タイムアウト", "\(Int(ServerConfig.requestTimeoutInterval))秒")
                configRow("設定状態", apiService.appConfig != nil ? "読込済み" : "未取得")
            }
        }

        // 同期データサマリー
        if apiService.appConfig != nil {
            DashboardCard(title: "サーバー設定データ") {
                VStack(alignment: .leading, spacing: 6) {
                    configRow("PI_LOCATIONS", "\(apiService.appConfig?.PI_LOCATIONS?.count ?? 0)台")
                    configRow("BEACON_POSITIONS", "\(apiService.appConfig?.BEACON_POSITIONS?.count ?? 0)件")
                    configRow("MINOR_ID_MAP", "\(apiService.appConfig?.MINOR_ID_TO_PI_NAME_MAP?.count ?? 0)件")
                    configRow("FLOOR_BOUNDARY", "\(apiService.appConfig?.FLOOR_BOUNDARY?.count ?? 0)点")
                    let objs = apiService.appConfig?.FLOOR_OBJECTS ?? []
                    let objSummary = Dictionary(grouping: objs, by: { $0.type })
                        .sorted { $0.key < $1.key }
                        .map { "\($0.key):\($0.value.count)" }
                        .joined(separator: " ")
                    configRow("FLOOR_OBJECTS", "\(objs.count)件" + (objs.isEmpty ? "" : " (\(objSummary))"))
                    let zones = apiService.appConfig?.ZONE_BOUNDARIES ?? [:]
                    let zoneNames = zones.keys.sorted().joined(separator: ", ")
                    configRow("ZONE_BOUNDARIES", "\(zones.count)ゾーン" + (zones.isEmpty ? "" : " (\(zoneNames))"))
                    configRow("CHAIR_CENTERS", "\(apiService.appConfig?.CHAIR_CENTERS?.count ?? 0)脚")
                    configRow("CENTER_LINES", "\(apiService.appConfig?.CENTER_LINES?.count ?? 0)本")
                    configRow("CALIBRATION", apiService.appConfig?.CALIBRATION?.scale_mm_per_px != nil ? "設定済み" : "未設定")
                    configRow("FLOORPLAN", apiService.appConfig?.FLOORPLAN_IMAGE?.url ?? "未設定")
                }
            }
        }

        // 更新ボタン
        Button(action: { apiService.fetchConfig() }) {
            HStack {
                Image(systemName: "arrow.clockwise")
                Text("設定を再読込")
            }
            .font(.caption.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(AppTheme.accent)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
    }

    private func configRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundColor(AppTheme.textPrimary)
        }
    }
}

// MARK: - 壁・机配置セクション
struct FloorObjectSection: View {
    @ObservedObject var apiService: APIService
    @State private var entries: [FloorObjectEntry] = []
    @State private var isSaving = false
    @State private var saveMessage = ""

    // タップ配置用の状態
    @State private var drawingType: String = "wall"
    @State private var firstPoint: CGPoint? = nil      // 物理座標(mm)での1点目
    @State private var isDrawing = false                // 描画モード ON/OFF

    // 1点配置タイプ（固定サイズ）
    private static let singlePointTypes: Set<String> = ["plant", "monitor"]
    // 植物の固定半径(mm)
    private static let plantRadius: Double = 250
    // モニターの固定サイズ(mm)
    private static let monitorSize: Double = 300

    struct FloorObjectEntry: Identifiable {
        let id = UUID()
        var type: String = "wall"  // "wall", "desk", "pillar", "shelf", "plant", "chair", "monitor", "window"
        var x1: String = "0"
        var y1: String = "0"
        var x2: String = "1000"
        var y2: String = "0"
        var height: String = ""
        var heightStart: String = ""  // 窓ガラス: 高さの始点(mm)
        var label: String = ""
        var color: String = ""  // hex色 例: "#FF6600"（空=デフォルト色）
        var count: String = "1"    // 椅子: 直線上に配置する個数
        var rotation: String = "0" // 椅子: 向き（度数、0=北向き、時計回り）
    }

    var body: some View {
        VStack(spacing: 12) {
            // タップ配置ツールバー
            DashboardCard(title: "タップ配置") {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        // 種類選択（横スクロール対応）
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(["wall", "desk", "pillar", "shelf", "plant", "chair", "monitor", "window"], id: \.self) { t in
                                    let label: String = {
                                        switch t {
                                        case "wall": return "壁"
                                        case "desk": return "机"
                                        case "pillar": return "柱"
                                        case "shelf": return "棚"
                                        case "plant": return "植物"
                                        case "chair": return "椅子"
                                        case "monitor": return "モニター"
                                        case "window": return "窓"
                                        default: return t
                                        }
                                    }()
                                    let icon: String = {
                                        switch t {
                                        case "wall": return "line.diagonal"
                                        case "desk": return "rectangle"
                                        case "pillar": return "square.fill"
                                        case "shelf": return "books.vertical"
                                        case "plant": return "leaf"
                                        case "chair": return "chair"
                                        case "monitor": return "desktopcomputer"
                                        case "window": return "window.casement"
                                        default: return "square"
                                        }
                                    }()
                                    Button {
                                        drawingType = t
                                    } label: {
                                        HStack(spacing: 2) {
                                            Image(systemName: icon).font(.system(size: 9))
                                            Text(label).font(.system(size: 10, weight: .semibold))
                                        }
                                        .foregroundColor(drawingType == t ? .white : AppTheme.textSecondary)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 5)
                                        .background(drawingType == t ? AppTheme.accent : Color.black.opacity(0.2))
                                        .cornerRadius(6)
                                    }
                                }
                            }
                        }

                        // 描画モード ON/OFF
                        Button {
                            isDrawing.toggle()
                            if !isDrawing { firstPoint = nil }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: isDrawing ? "pencil.circle.fill" : "pencil.circle")
                                    .font(.system(size: 14))
                                Text(isDrawing ? "配置中" : "配置")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(isDrawing ? .white : AppTheme.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(isDrawing ? Color.green : Color.black.opacity(0.2))
                            .cornerRadius(6)
                        }
                    }

                    // ステータスメッセージ
                    if isDrawing {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            if Self.singlePointTypes.contains(drawingType) {
                                Text(drawingType == "monitor"
                                     ? "マップをタップして配置位置を指定（向きは角度で設定）"
                                     : "マップをタップして配置位置を指定")
                                    .font(.system(size: 10))
                                    .foregroundColor(AppTheme.textSecondary)
                            } else {
                                Text(firstPoint == nil
                                     ? "マップをタップして始点を指定"
                                     : "マップをタップして終点を指定（長押しでキャンセル）")
                                    .font(.system(size: 10))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                        }
                        .transition(.opacity)
                    }
                }
            }

            // プレビュー (タップ配置対応)
            DashboardCard(title: "プレビュー") {
                floorPreview
            }

            // オブジェクトリスト
            DashboardCard(title: "フロアオブジェクト (\(entries.count)件)") {
                VStack(spacing: 0) {
                    // ヘッダー
                    HStack(spacing: 4) {
                        Text("種類").frame(width: 50)
                        Text("X1").frame(width: 50)
                        Text("Y1").frame(width: 50)
                        Text("X2").frame(width: 50)
                        Text("Y2").frame(width: 50)
                        Text("高さ").frame(width: 36)
                        Text("色").frame(width: 36)
                        Spacer()
                        Text("").frame(width: 24)
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundColor(AppTheme.accent)
                    .padding(.vertical, 4)

                    // 行
                    ForEach($entries) { $entry in
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                Picker("", selection: $entry.type) {
                                    Text("壁").tag("wall")
                                    Text("机").tag("desk")
                                    Text("柱").tag("pillar")
                                    Text("棚").tag("shelf")
                                    Text("植物").tag("plant")
                                    Text("椅子").tag("chair")
                                    Text("モニター").tag("monitor")
                                    Text("窓").tag("window")
                                }
                                .pickerStyle(.menu)
                                .frame(width: 50)
                                .tint(AppTheme.textPrimary)
                                .scaleEffect(0.8)

                                objField($entry.x1, width: 50)
                                objField($entry.y1, width: 50)
                                // 1点配置タイプはX2/Y2を非表示（自動計算）
                                if Self.singlePointTypes.contains(entry.type) {
                                    Text("--").font(.system(size: 9)).foregroundColor(AppTheme.textSecondary).frame(width: 50)
                                    Text("--").font(.system(size: 9)).foregroundColor(AppTheme.textSecondary).frame(width: 50)
                                } else {
                                    objField($entry.x2, width: 50)
                                    objField($entry.y2, width: 50)
                                }
                                objField($entry.height, width: 36, placeholder: "自動")
                                // 色選択
                                colorPickerCell($entry.color)
                                    .frame(width: 36)
                                Spacer()
                                Button { withAnimation { entries.removeAll { $0.id == entry.id } } } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red.opacity(0.7))
                                        .font(.caption)
                                }
                                .frame(width: 24)
                            }
                            // 椅子・モニターの場合: 個数・向き入力行
                            if entry.type == "chair" {
                                HStack(spacing: 6) {
                                    Spacer().frame(width: 50)
                                    Text("個数:").font(.system(size: 9, weight: .semibold)).foregroundColor(AppTheme.accent)
                                    objField($entry.count, width: 36, placeholder: "1")
                                    Text("向き(°):").font(.system(size: 9, weight: .semibold)).foregroundColor(AppTheme.accent)
                                    objField($entry.rotation, width: 40, placeholder: "0")
                                    Text("0=北,90=東").font(.system(size: 8)).foregroundColor(AppTheme.textSecondary)
                                    Spacer()
                                }
                            }
                            if entry.type == "monitor" {
                                HStack(spacing: 6) {
                                    Spacer().frame(width: 50)
                                    Text("画面向き(°):").font(.system(size: 9, weight: .semibold)).foregroundColor(AppTheme.accent)
                                    objField($entry.rotation, width: 40, placeholder: "0")
                                    Text("0=北,90=東").font(.system(size: 8)).foregroundColor(AppTheme.textSecondary)
                                    Spacer()
                                }
                            }
                            if entry.type == "window" {
                                HStack(spacing: 6) {
                                    Spacer().frame(width: 50)
                                    Text("下端(mm):").font(.system(size: 9, weight: .semibold)).foregroundColor(AppTheme.accent)
                                    objField($entry.heightStart, width: 44, placeholder: "800")
                                    Text("上端(mm):").font(.system(size: 9, weight: .semibold)).foregroundColor(AppTheme.accent)
                                    objField($entry.height, width: 44, placeholder: "2000")
                                    Spacer()
                                }
                            }
                        }
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(4)
                    }

                    // 追加ボタン
                    Button {
                        withAnimation { entries.append(FloorObjectEntry()) }
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("オブジェクト追加")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppTheme.textPrimary)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(Color(hex: "#40407a"))
                        .cornerRadius(6)
                    }
                    .padding(.top, 8)
                }
            }

            // 説明
            DashboardCard(title: "使い方") {
                VStack(alignment: .leading, spacing: 4) {
                    helpRow("配置", "「配置」ボタンON → マップをタップで配置")
                    helpRow("壁", "始点→終点の2タップで壁パネル")
                    helpRow("机", "2タップで対角の矩形の机")
                    helpRow("柱", "2タップで対角の矩形の柱")
                    helpRow("棚", "2タップで対角の矩形の棚")
                    helpRow("植物", "1タップで固定サイズの観葉植物")
                    helpRow("椅子", "2タップで直線指定→個数分を均等配置、向き指定可")
                    helpRow("モニター", "1タップで固定サイズのモニター、向き指定可")
                    helpRow("窓", "壁と同様に2タップ配置。下端/上端で高さ範囲を指定")
                    helpRow("高さ", "未入力: 壁2800, 机700, 柱2800, 棚1500, 植物1200, 椅子450, 窓800-2000mm")
                    helpRow("色", "各オブジェクトの色を個別指定可能")
                    helpRow("取消", "配置中に長押しで始点をキャンセル")
                    Text("※ 座標は手動入力でも変更可能")
                        .font(.system(size: 9))
                        .foregroundColor(AppTheme.textSecondary)
                        .padding(.top, 2)
                }
            }

            // 保存ボタン
            DashboardCard(title: "保存") {
                if !saveMessage.isEmpty {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundColor(saveMessage.contains("成功") ? .green : .red)
                }

                Button {
                    saveFloorObjects()
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView().tint(.white)
                        }
                        Text("保存")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.accent)
                    .cornerRadius(8)
                }
                .disabled(isSaving)
            }
        }
        .onAppear { loadExisting() }
    }

    // フロアプレビュー（タップ配置対応）
    @ViewBuilder
    private var floorPreview: some View {
        let imgW = apiService.appConfig?.FLOORPLAN_IMAGE?.width ?? 1483
        let imgH = apiService.appConfig?.FLOORPLAN_IMAGE?.height ?? 1753
        let aspect = imgW / imgH

        ZStack {
            if let url = apiService.floorplanURL() {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable()
                    default: Color(hex: "#303060")
                    }
                }
            } else {
                Image("kenkyushitsu_zahyo").resizable()
            }

            GeometryReader { geo in
                // 既存オブジェクト描画
                ForEach(entries) { entry in
                    let p1 = mmToView(Double(entry.x1) ?? 0, Double(entry.y1) ?? 0, size: geo.size)
                    let p2 = mmToView(Double(entry.x2) ?? 0, Double(entry.y2) ?? 0, size: geo.size)

                    if entry.type == "wall" {
                        let wallColor = entry.color.isEmpty ? Color.cyan : colorFromHex(entry.color)
                        Path { path in
                            path.move(to: p1)
                            path.addLine(to: p2)
                        }
                        .stroke(wallColor, lineWidth: 2)
                    } else if entry.type == "plant" {
                        // 植物: アイコン表示
                        let center = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
                        let objColor = entry.color.isEmpty ? Color.green : colorFromHex(entry.color)
                        Circle()
                            .fill(objColor.opacity(0.4))
                            .frame(width: 14, height: 14)
                            .position(center)
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 8))
                            .foregroundColor(objColor)
                            .position(center)
                    } else if entry.type == "monitor" {
                        // モニター: 中心にアイコン
                        let center = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
                        let monColor = entry.color.isEmpty ? Color.blue : colorFromHex(entry.color)
                        Rectangle()
                            .fill(monColor.opacity(0.3))
                            .frame(width: 14, height: 10)
                            .position(center)
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 8))
                            .foregroundColor(monColor)
                            .position(center)
                    } else if entry.type == "window" {
                        // 窓ガラス: 壁線上に水色の線
                        let winColor = entry.color.isEmpty ? Color.cyan.opacity(0.6) : colorFromHex(entry.color).opacity(0.6)
                        Path { path in
                            path.move(to: p1)
                            path.addLine(to: p2)
                        }
                        .stroke(winColor, lineWidth: 4)
                        // 中央にアイコン
                        let wCenter = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
                        Image(systemName: "window.casement")
                            .font(.system(size: 8))
                            .foregroundColor(.cyan)
                            .position(wCenter)
                    } else if entry.type == "chair" {
                        // 椅子: 直線上に複数表示
                        let chairColor = entry.color.isEmpty ? Color.gray : colorFromHex(entry.color)
                        let cnt = max(1, Int(entry.count) ?? 1)
                        // 配置直線を表示
                        Path { path in
                            path.move(to: p1)
                            path.addLine(to: p2)
                        }
                        .stroke(chairColor.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        // 各椅子位置にマーカー
                        ForEach(0..<cnt, id: \.self) { ci in
                            let t = cnt == 1 ? 0.5 : Double(ci) / Double(cnt - 1)
                            let cx = p1.x + (p2.x - p1.x) * t
                            let cy = p1.y + (p2.y - p1.y) * t
                            Circle()
                                .fill(chairColor.opacity(0.4))
                                .frame(width: 10, height: 10)
                                .position(x: cx, y: cy)
                            Image(systemName: "chair.fill")
                                .font(.system(size: 7))
                                .foregroundColor(chairColor)
                                .position(x: cx, y: cy)
                        }
                    } else {
                        let rect = CGRect(
                            x: min(p1.x, p2.x), y: min(p1.y, p2.y),
                            width: abs(p2.x - p1.x), height: abs(p2.y - p1.y)
                        )
                        let hasCustomColor = !entry.color.isEmpty
                        let baseColor: Color = hasCustomColor ? colorFromHex(entry.color) : {
                            switch entry.type {
                            case "desk": return Color.orange
                            case "pillar": return Color.purple
                            case "shelf": return Color.brown
                            default: return Color.orange
                            }
                        }()
                        Rectangle()
                            .fill(baseColor.opacity(0.3))
                            .border(baseColor, width: 1.5)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }

                // 描画中の1点目マーカー
                if isDrawing, let fp = firstPoint {
                    let viewPt = mmToView(fp.x, fp.y, size: geo.size)
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)
                        .position(viewPt)
                    Circle()
                        .stroke(Color.green, lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                        .position(viewPt)
                }

                // 描画モード中のタップエリア（透明）
                if isDrawing {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            handleTap(at: location, in: geo.size)
                        }
                        .onLongPressGesture {
                            // 長押しで1点目をキャンセル
                            withAnimation { firstPoint = nil }
                        }
                }
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .cornerRadius(8)
        .clipped()
        .overlay(
            // 描画モード中のボーダー表示
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDrawing ? Color.green : Color.clear, lineWidth: 2)
        )
    }

    private func mmToView(_ mmX: Double, _ mmY: Double, size: CGSize) -> CGPoint {
        let cal = apiService.appConfig?.CALIBRATION
        let imgW = apiService.appConfig?.FLOORPLAN_IMAGE?.width ?? 1483
        let imgH = apiService.appConfig?.FLOORPLAN_IMAGE?.height ?? 1753
        let originX = cal?.origin_px?.x ?? 116.25
        let originY = cal?.origin_px?.y ?? 340.75
        let scale = cal?.scale_mm_per_px ?? 6.335
        let pxX = mmX / scale + originX
        let pxY = imgH - (-mmY / scale + originY)
        return CGPoint(x: pxX / imgW * size.width, y: pxY / imgH * size.height)
    }

    // ビュー座標 → 物理座標(mm) への逆変換
    private func viewToMm(_ viewX: Double, _ viewY: Double, in size: CGSize) -> CGPoint {
        let cal = apiService.appConfig?.CALIBRATION
        let imgW = apiService.appConfig?.FLOORPLAN_IMAGE?.width ?? 1483
        let imgH = apiService.appConfig?.FLOORPLAN_IMAGE?.height ?? 1753
        let originX = cal?.origin_px?.x ?? 116.25
        let originY = cal?.origin_px?.y ?? 340.75
        let scale = cal?.scale_mm_per_px ?? 6.335
        // ビュー→ピクセル
        let pxX = viewX / size.width * imgW
        let pxY = viewY / size.height * imgH
        // ピクセル→物理(mm)
        let mmX = (pxX - originX) * scale
        let mmY = -((imgH - pxY) - originY) * scale
        return CGPoint(x: round(mmX), y: round(mmY))
    }

    // タップ処理: 1点タイプは即配置、2点タイプは始点→終点
    private func handleTap(at location: CGPoint, in size: CGSize) {
        let mm = viewToMm(location.x, location.y, in: size)

        if Self.singlePointTypes.contains(drawingType) {
            // 1点配置: タップ位置を中心に固定サイズ
            let r: Double
            if drawingType == "monitor" { r = Self.monitorSize / 2 }
            else { r = Self.plantRadius }
            var newEntry = FloorObjectEntry(
                type: drawingType,
                x1: String(format: "%.0f", mm.x - r),
                y1: String(format: "%.0f", mm.y - r),
                x2: String(format: "%.0f", mm.x + r),
                y2: String(format: "%.0f", mm.y + r)
            )
            if drawingType == "monitor" {
                newEntry.rotation = "0"
            }
            withAnimation { entries.append(newEntry) }
        } else if firstPoint == nil {
            // 2点タイプの1点目を記録
            withAnimation { firstPoint = CGPoint(x: mm.x, y: mm.y) }
        } else {
            // 2点目 → オブジェクト作成
            let fp = firstPoint!
            var newEntry = FloorObjectEntry(
                type: drawingType,
                x1: String(format: "%.0f", fp.x),
                y1: String(format: "%.0f", fp.y),
                x2: String(format: "%.0f", mm.x),
                y2: String(format: "%.0f", mm.y)
            )
            // 椅子のデフォルト個数
            if drawingType == "chair" {
                newEntry.count = "1"
                newEntry.rotation = "0"
            }
            withAnimation {
                entries.append(newEntry)
                firstPoint = nil
            }
        }
    }

    // 色選択セル（hex文字列 ↔ Color変換）
    private func colorPickerCell(_ hexBinding: Binding<String>) -> some View {
        let currentColor = colorFromHex(hexBinding.wrappedValue)
        return ColorPicker("", selection: Binding<Color>(
            get: { currentColor },
            set: { newColor in
                hexBinding.wrappedValue = hexFromColor(newColor)
            }
        ))
        .labelsHidden()
        .scaleEffect(0.75)
    }

    private func colorFromHex(_ hex: String) -> Color {
        guard !hex.isEmpty else { return .gray }
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return .gray }
        let r = Double((val >> 16) & 0xFF) / 255
        let g = Double((val >> 8) & 0xFF) / 255
        let b = Double(val & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }

    private func hexFromColor(_ color: Color) -> String {
        let c = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    private func objField(_ binding: Binding<String>, width: CGFloat, placeholder: String = "") -> some View {
        TextField(placeholder, text: binding)
            .keyboardType(.numbersAndPunctuation)
            .font(.system(size: 10))
            .foregroundColor(AppTheme.textPrimary)
            .padding(3)
            .background(Color.black.opacity(0.15))
            .cornerRadius(3)
            .frame(width: width)
    }

    private func helpRow(_ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(AppTheme.accent)
                .frame(width: 28, alignment: .leading)
            Text(desc)
                .font(.system(size: 10))
                .foregroundColor(AppTheme.textSecondary)
        }
    }

    private func loadExisting() {
        guard let objects = apiService.appConfig?.FLOOR_OBJECTS else { return }
        entries = objects.map { obj in
            FloorObjectEntry(
                type: obj.type,
                x1: String(format: "%.0f", obj.x1),
                y1: String(format: "%.0f", obj.y1),
                x2: String(format: "%.0f", obj.x2),
                y2: String(format: "%.0f", obj.y2),
                height: obj.height.map { String(format: "%.0f", $0) } ?? "",
                heightStart: obj.height_start.map { String(format: "%.0f", $0) } ?? "",
                label: obj.label ?? "",
                color: obj.color ?? "",
                count: obj.count.map { String($0) } ?? "1",
                rotation: obj.rotation.map { String(format: "%.0f", $0) } ?? "0"
            )
        }
    }

    private func saveFloorObjects() {
        isSaving = true
        saveMessage = ""

        let objects: [[String: Any]] = entries.compactMap { entry in
            guard let x1 = Double(entry.x1), let y1 = Double(entry.y1),
                  let x2 = Double(entry.x2), let y2 = Double(entry.y2) else { return nil }
            var dict: [String: Any] = [
                "type": entry.type,
                "x1": x1, "y1": y1,
                "x2": x2, "y2": y2
            ]
            if let h = Double(entry.height), h > 0 { dict["height"] = h }
            if !entry.label.isEmpty { dict["label"] = entry.label }
            if !entry.color.isEmpty { dict["color"] = entry.color }
            if entry.type == "chair" {
                if let c = Int(entry.count), c > 0 { dict["count"] = c }
                if let r = Double(entry.rotation) { dict["rotation"] = r }
            }
            if entry.type == "monitor" {
                if let r = Double(entry.rotation) { dict["rotation"] = r }
            }
            if entry.type == "window" {
                if let hs = Double(entry.heightStart), hs >= 0 { dict["height_start"] = hs }
            }
            return dict
        }

        Task {
            let (_, message) = await apiService.updateFloorObjects(objects: objects)
            isSaving = false
            saveMessage = message
        }
    }
}
