//
//  SocialView.swift
//  tohata_ios_02
//
//  ソーシャル機能タブ: スキル検索、近くのマッチ、コラボボード、ランチマッチ、交流分析
//

import SwiftUI

// MARK: - ソーシャルタブ
struct SocialTab: View {
    @ObservedObject var apiService: APIService
    let beaconId: String  // UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    var onHighlightUser: ((HighlightTarget) -> Void)? = nil
    @State private var showGuide = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with help button
            HStack {
                Text("ソーシャル")
                    .font(.title2.weight(.bold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Button { showGuide = true } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.title3)
                        .foregroundColor(AppTheme.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppTheme.background)

            ScrollView {
                VStack(spacing: 14) {
                    SkillSearchSection(apiService: apiService, onHighlightUser: onHighlightUser)
                    NearbyMatchSection(apiService: apiService, beaconId: beaconId, onHighlightUser: onHighlightUser)
                    CollabBoardSection(apiService: apiService, beaconId: beaconId, onHighlightUser: onHighlightUser)
                    LunchMatchSection(apiService: apiService, beaconId: beaconId, onHighlightUser: onHighlightUser)
                    InteractionSection(apiService: apiService, beaconId: beaconId)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .refreshable {
                await refreshAll()
            }
        }
        .background(AppTheme.background)
        .onAppear {
            // 基本データのみ即時取得（各セクション固有のデータはonAppearで遅延取得）
            Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await apiService.fetchPersonPositions() }
                    group.addTask { await apiService.fetchAllProfiles() }
                }
            }
        }
        .refreshable {
            await refreshAll()
        }
        .sheet(isPresented: $showGuide) {
            SocialGuideSheet()
        }
    }

    /// プルリフレッシュ時は全API一括取得
    private func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await apiService.fetchPersonPositions() }
            group.addTask { await apiService.fetchAllProfiles() }
            group.addTask { await apiService.fetchNearbyMatches(beaconId: beaconId) }
            group.addTask { await apiService.fetchCollabPosts(hours: 12) }
            group.addTask { await apiService.fetchTodaysLunchMatch(beaconId: beaconId) }
            group.addTask { await apiService.fetchMyInteractions(beaconId: beaconId) }
            group.addTask { await apiService.fetchInteractionStats() }
        }
    }
}

// MARK: - Feature 1: Skill Search
struct SkillSearchSection: View {
    @ObservedObject var apiService: APIService
    var onHighlightUser: ((HighlightTarget) -> Void)? = nil
    @State private var query = ""
    @State private var profileSheetResult: SkillSearchResult? = nil

    var body: some View {
        DashboardCard(title: "スキルマッチング") {
            // Text field + search button
            HStack {
                TextField("スキルで検索 (例: Python)", text: $query)
                    .font(.caption)
                    .foregroundColor(AppTheme.textPrimary)
                    .padding(8)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(6)
                Button("検索") {
                    Task { await apiService.searchBySkill(skill: query) }
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.accent)
                .cornerRadius(6)
            }

            // Results
            if apiService.skillSearchResults.isEmpty && !query.isEmpty {
                Text("該当するユーザーが見つかりません")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.vertical, 8)
            }

            ForEach(apiService.skillSearchResults) { result in
                skillResultRow(result)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let pos = result.position, let x = pos.x, let y = pos.y {
                            // 位置あり → ヒートマップでハイライト
                            onHighlightUser?(HighlightTarget(
                                beaconId: result.beacon_id,
                                userName: result.user_name,
                                x: x,
                                y: y
                            ))
                        } else {
                            // 位置なし → プロフィール表示
                            profileSheetResult = result
                        }
                    }
            }
            // ...existing code...
            // ...existing code...
        }
        .sheet(item: $profileSheetResult) { result in
            let prof = apiService.profiles.first { $0.beacon_id == result.beacon_id }
            UserDetailSheet(
                userName: result.user_name,
                department: result.department,
                jobTitle: prof?.job_title,
                profileImage: result.profile_image,
                status: nil,
                zone: nil,
                matchReason: nil,
                skills: prof?.skills,
                hobbies: prof?.hobbies
            )
        }
    }

    // Each result: small avatar with status lamp + name + department + matched skill tag + position status
    private func skillResultRow(_ result: SkillSearchResult) -> some View {
        let personStatus = apiService.persons.first { $0.beacon_id == result.beacon_id }?.status
        return HStack(spacing: 8) {
            // Profile icon with status lamp
            skillAvatarWithStatus(result.profile_image, name: result.user_name, status: personStatus)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.user_name ?? "Unknown")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                Text(result.department ?? "")
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textSecondary)
            }

            Spacer()

            if let matched = result.matched_skill {
                Text(matched)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(AppTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.accent.opacity(0.15))
                    .cornerRadius(4)
            }

            // Position availability dot (tappable hint)
            if let pos = result.position, pos.x != nil {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.accent)
            } else {
                Circle().fill(Color.gray).frame(width: 8, height: 8)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.15))
        .cornerRadius(6)
    }

    private func skillAvatarWithStatus(_ imageURL: String?, name: String?, status: String?) -> some View {
        ZStack(alignment: .bottomTrailing) {
            skillAvatar(imageURL, name: name)
            Circle()
                .fill(profileStatusColor(status))
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(AppTheme.background, lineWidth: 1.5))
                .offset(x: 2, y: 2)
        }
    }

    private func skillAvatar(_ imageURL: String?, name: String?) -> some View {
        Group {
            if let imgPath = imageURL,
               let url = URL(string: ServerConfig.baseURL + imgPath) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    skillAvatarPlaceholder(name: name)
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            } else {
                skillAvatarPlaceholder(name: name)
            }
        }
    }

    private func skillAvatarPlaceholder(name: String?) -> some View {
        ZStack {
            Circle().fill(AppTheme.accent.opacity(0.3))
            Text(String((name ?? "?").prefix(1)))
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
        }
        .frame(width: 32, height: 32)
    }
}

// MARK: - Feature 2: Nearby Matches
struct NearbyMatchSection: View {
    @ObservedObject var apiService: APIService
    let beaconId: String
    var onHighlightUser: ((HighlightTarget) -> Void)? = nil
    @State private var profileSheetMatch: NearbyMatch? = nil

    var body: some View {
        DashboardCard(title: "近くのマッチ (\(apiService.nearbyMatches.count)人)") {
            if apiService.nearbyMatches.isEmpty {
                Text("近くにマッチする人はいません")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }

            ForEach(apiService.nearbyMatches) { match in
                HStack(spacing: 8) {
                    // アバター + ステータスランプ（タップでハイライト/プロフィール）
                    nearbyAvatarWithStatus(match.profile_image, name: match.user_name, beaconId: match.beacon_id)
                        .contentShape(Circle())
                        .onTapGesture {
                            if let pos = match.position, let x = pos.x, let y = pos.y {
                                onHighlightUser?(HighlightTarget(
                                    beaconId: match.beacon_id,
                                    userName: match.user_name,
                                    x: x, y: y
                                ))
                            } else {
                                profileSheetMatch = match
                            }
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(match.user_name ?? "Unknown")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white)
                            Text(String(format: "%.1fm", match.distance_mm / 1000.0))
                                .font(.system(size: 9))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        // Matching fields as tags
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(match.matching_fields, id: \.self) { field in
                                    Text(field)
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundColor(AppTheme.accent)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(AppTheme.accent.opacity(0.15))
                                        .cornerRadius(3)
                                }
                            }
                        }
                    }
                    Spacer()
                }
                .padding(8)
                .background(Color.black.opacity(0.15))
                .cornerRadius(6)
            }

            // Refresh button
            Button(action: {
                Task { await apiService.fetchNearbyMatches(beaconId: beaconId) }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("更新")
                }
                .font(.caption)
                .foregroundColor(AppTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
        }
        .onAppear {
            if apiService.nearbyMatches.isEmpty {
                Task { await apiService.fetchNearbyMatches(beaconId: beaconId) }
            }
        }
        .sheet(item: $profileSheetMatch) { match in
            let prof = apiService.profiles.first { $0.beacon_id == match.beacon_id }
            UserDetailSheet(
                userName: match.user_name,
                department: prof?.department,
                jobTitle: prof?.job_title,
                profileImage: match.profile_image,
                status: match.status,
                zone: nil,
                matchReason: match.matching_fields.joined(separator: ", "),
                skills: prof?.skills,
                hobbies: prof?.hobbies
            )
        }
    }

    private func nearbyAvatarWithStatus(_ imagePath: String?, name: String?, beaconId: String) -> some View {
        let personStatus = apiService.persons.first { $0.beacon_id == beaconId }?.status
        return ZStack(alignment: .bottomTrailing) {
            nearbyAvatar(imagePath, name: name)
            Circle()
                .fill(profileStatusColor(personStatus))
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(AppTheme.background, lineWidth: 1.5))
                .offset(x: 2, y: 2)
        }
    }

    private func nearbyAvatar(_ imagePath: String?, name: String?) -> some View {
        Group {
            if let imgPath = imagePath,
               let url = URL(string: ServerConfig.baseURL + imgPath) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    nearbyAvatarPlaceholder(name: name)
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            } else {
                nearbyAvatarPlaceholder(name: name)
            }
        }
    }

    private func nearbyAvatarPlaceholder(name: String?) -> some View {
        ZStack {
            Circle().fill(AppTheme.accent.opacity(0.3))
            Text(String((name ?? "?").prefix(1)))
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
        }
        .frame(width: 32, height: 32)
    }
}

// MARK: - Feature 3: Collaboration Board
struct CollabBoardSection: View {
    @ObservedObject var apiService: APIService
    let beaconId: String
    var onHighlightUser: ((HighlightTarget) -> Void)? = nil
    @State private var showNewPost = false
    @State private var selectedPost: CollabPost? = nil
    @State private var filterType: String = "all"
    @State private var sortMode: String = "newest"
    @State private var showUserDetail: Bool = false
    @State private var detailTargetBeaconId: String? = nil

    private let postTypeFilters: [(String, String)] = [
        ("all", "すべて"),
        ("help_wanted", "助けを求む"),
        ("reviewer_needed", "レビュー"),
        ("pair_programming", "ペアプロ"),
        ("question", "質問"),
        ("offer", "お手伝い"),
    ]

    private let sortOptions: [(String, String)] = [
        ("newest", "新しい順"),
        ("responses", "応答数順"),
    ]

    private var filteredAndSortedPosts: [CollabPost] {
        var posts = apiService.collabPosts
        if filterType != "all" {
            posts = posts.filter { $0.post_type == filterType }
        }
        if sortMode == "responses" {
            posts.sort { ($0.response_count ?? 0) > ($1.response_count ?? 0) }
        }
        return posts
    }

    var body: some View {
        DashboardCard(title: "コラボレーションボード") {
            // Create button
            Button(action: { showNewPost = true }) {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("投稿する")
                }
                .font(.caption.weight(.medium))
                .foregroundColor(AppTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(AppTheme.accent.opacity(0.1))
                .cornerRadius(6)
            }

            // Filter & Sort row
            VStack(spacing: 6) {
                // Type filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(postTypeFilters, id: \.0) { value, label in
                            Button {
                                filterType = value
                                refreshPosts()
                            } label: {
                                Text(label)
                                    .font(.system(size: 10, weight: filterType == value ? .bold : .regular))
                                    .foregroundColor(filterType == value ? .white : AppTheme.textSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(filterType == value ? AppTheme.accent.opacity(0.6) : Color.white.opacity(0.08))
                                    .cornerRadius(10)
                            }
                        }
                    }
                }
                // Sort picker
                HStack {
                    Text("12時間以内")
                        .font(.system(size: 9))
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                    Menu {
                        ForEach(sortOptions, id: \.0) { value, label in
                            Button {
                                sortMode = value
                            } label: {
                                HStack {
                                    Text(label)
                                    if sortMode == value {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 9))
                            Text(sortOptions.first { $0.0 == sortMode }?.1 ?? "")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(AppTheme.accent)
                    }
                }
            }

            if filteredAndSortedPosts.isEmpty {
                Text("投稿はまだありません")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.vertical, 12)
            }

            VStack(spacing: 0) {
                ForEach(filteredAndSortedPosts) { post in
                    collabPostRow(post)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedPost = post }
                }
            }
            .sheet(isPresented: $showUserDetail) {
                if let bid = detailTargetBeaconId {
                    let pPos = apiService.persons.first { $0.beacon_id == bid }
                    let prof = apiService.profiles.first { $0.beacon_id == bid }
                    let cPost = apiService.collabPosts.first { $0.beacon_id == bid }
                    let target = HighlightTarget(
                        beaconId: bid,
                        userName: pPos?.user_name ?? prof?.user_name ?? cPost?.user_name,
                        x: pPos?.estimated_x,
                        y: pPos?.estimated_y
                    )
                    UserDetailSheet(
                        userName: pPos?.user_name ?? prof?.user_name ?? cPost?.user_name,
                        department: pPos?.department ?? prof?.department,
                        jobTitle: pPos?.job_title ?? prof?.job_title,
                        profileImage: cPost?.profile_image ?? pPos?.profile_image ?? prof?.profile_image,
                        status: pPos?.status,
                        zone: nil,
                        matchReason: nil,
                        skills: prof?.skills,
                        hobbies: prof?.hobbies,
                        highlightTarget: target,
                        onHighlightUser: onHighlightUser
                    )
                }
            }
        }
        .onAppear {
            if apiService.collabPosts.isEmpty {
                refreshPosts()
            }
        }
        .sheet(isPresented: $showNewPost) {
            NewCollabPostSheet(apiService: apiService, beaconId: beaconId, isPresented: $showNewPost)
        }
        .sheet(item: $selectedPost) { post in
            CollabPostDetailSheet(apiService: apiService, post: post, beaconId: beaconId, onHighlightUser: onHighlightUser, onDismiss: {
                selectedPost = nil
                refreshPosts()
            })
        }
    }

    private func refreshPosts() {
        Task {
            await apiService.fetchCollabPosts(
                hours: 12,
                postType: filterType == "all" ? nil : filterType
            )
        }
    }

    private func collabPostRow(_ post: CollabPost) -> some View {
        let personPos = apiService.persons.first { $0.beacon_id == post.beacon_id }

        return VStack(alignment: .leading, spacing: 6) {
            // User info row: avatar + status lamp + name
            HStack(spacing: 6) {
                collabAvatarWithStatus(
                    post.profile_image,
                    name: post.user_name,
                    status: personPos?.status
                )
                .contentShape(Circle())
                .onTapGesture {
                    // 位置あり → ハイライト、位置なし → プロフィール
                    if let x = personPos?.estimated_x, let y = personPos?.estimated_y {
                        onHighlightUser?(HighlightTarget(
                            beaconId: post.beacon_id,
                            userName: post.user_name,
                            x: x, y: y
                        ))
                    } else {
                        detailTargetBeaconId = post.beacon_id
                        showUserDetail = true
                    }
                }
                Text(post.user_name ?? "匿名")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                if let date = post.created_at {
                    Spacer()
                    Text(collabTimeAgo(date))
                        .font(.system(size: 9))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
            // Post content row
            HStack(spacing: 4) {
                Image(systemName: postTypeIcon(post.post_type))
                    .font(.system(size: 9))
                    .foregroundColor(postTypeColor(post.post_type))
                Text(post.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                if post.is_skill_match == true {
                    Text("スキル一致")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(3)
                }
                if let count = post.response_count, count > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 8))
                        Text("\(count)")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(AppTheme.accent)
                }
            }
            if let skills = post.required_skills, !skills.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(skills.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }, id: \.self) { s in
                            Text(s)
                                .font(.system(size: 8))
                                .foregroundColor(AppTheme.accent)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(AppTheme.accent.opacity(0.1))
                                .cornerRadius(3)
                        }
                    }
                }
                .padding(.leading, 32)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.15))
        .cornerRadius(6)
    }

    private func collabAvatar(_ imageURL: String?, name: String?) -> some View {
        Group {
            if let urlStr = imageURL, !urlStr.isEmpty,
               let url = URL(string: ServerConfig.baseURL + urlStr) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    avatarPlaceholder(name: name)
                }
                .frame(width: 24, height: 24)
                .clipShape(Circle())
            } else {
                avatarPlaceholder(name: name)
            }
        }
    }

    private func collabAvatarWithStatus(_ imageURL: String?, name: String?, status: String?) -> some View {
        ZStack(alignment: .bottomTrailing) {
            collabAvatar(imageURL, name: name)
            // Status lamp
            Circle()
                .fill(profileStatusColor(status))
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(AppTheme.background, lineWidth: 1.5))
                .offset(x: 2, y: 2)
        }
    }

    private func avatarPlaceholder(name: String?) -> some View {
        ZStack {
            Circle().fill(AppTheme.accent.opacity(0.3))
            Text(String((name ?? "?").prefix(1)))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 24, height: 24)
    }

    private func collabTimeAgo(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let date = formatter.date(from: dateStr) else {
            return String(dateStr.prefix(10))
        }
        let minutes = Int(-date.timeIntervalSinceNow / 60)
        if minutes < 1 { return "たった今" }
        if minutes < 60 { return "\(minutes)分前" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)時間前" }
        return String(dateStr.prefix(10))
    }

    private func postTypeIcon(_ type: String) -> String {
        switch type {
        case "help_wanted": return "questionmark.circle"
        case "reviewer_needed": return "eye.circle"
        case "pair_programming": return "person.2"
        case "question": return "bubble.left.and.bubble.right"
        case "offer": return "hand.raised"
        default: return "doc.text"
        }
    }

    private func postTypeColor(_ type: String) -> Color {
        switch type {
        case "help_wanted": return .orange
        case "reviewer_needed": return .purple
        case "pair_programming": return .cyan
        case "question": return .yellow
        case "offer": return .green
        default: return .gray
        }
    }
}

// MARK: - Collaboration Post Detail Sheet
struct CollabPostDetailSheet: View {
    @ObservedObject var apiService: APIService
    let post: CollabPost
    let beaconId: String
    var onHighlightUser: ((HighlightTarget) -> Void)? = nil
    var onDismiss: () -> Void

    @State private var responses: [CollabPostResponse] = []
    @State private var newMessage = ""
    @State private var isSending = false
    @State private var showCloseConfirm = false
    @State private var showUserDetail: Bool = false
    @State private var detailTargetBeaconId: String? = nil
    @AppStorage(UserDefaultsConfig.Keys.userName) private var userName = ""
    @Environment(\.dismiss) private var dismiss

    private var isMyPost: Bool { post.beacon_id == beaconId }
    private var isClosed: Bool { post.status == "closed" }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Post header
                    postHeaderSection

                    // Description
                    if let desc = post.description, !desc.isEmpty {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.2))
                            .cornerRadius(8)
                    }

                    // Required skills
                    if let skills = post.required_skills, !skills.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("必要なスキル")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppTheme.textSecondary)
                            FlowLayout(spacing: 6) {
                                ForEach(skills.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }, id: \.self) { s in
                                    Text(s)
                                        .font(.caption)
                                        .foregroundColor(AppTheme.accent)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(AppTheme.accent.opacity(0.15))
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }

                    Divider().background(Color.gray.opacity(0.3))

                    // Responses section
                    responsesSection

                    // Reply input (if open)
                    if !isClosed {
                        replyInputSection
                    }
                }
                .padding()
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("投稿詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        onDismiss()
                        dismiss()
                    }
                }
                if isMyPost && !isClosed {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("解決済み") { showCloseConfirm = true }
                            .foregroundColor(.orange)
                    }
                }
            }
            .alert("投稿をクローズしますか？", isPresented: $showCloseConfirm) {
                Button("キャンセル", role: .cancel) {}
                Button("クローズ", role: .destructive) {
                    Task {
                        let _ = await apiService.closeCollabPost(postId: post.id, beaconId: beaconId)
                        onDismiss()
                        dismiss()
                    }
                }
            } message: {
                Text("クローズすると新しい応答を受け付けなくなります。")
            }
            .task {
                responses = await apiService.fetchCollabResponses(postId: post.id)
            }
        }
        .sheet(isPresented: $showUserDetail) {
            if let bid = detailTargetBeaconId {
                let pPos = apiService.persons.first { $0.beacon_id == bid }
                let prof = apiService.profiles.first { $0.beacon_id == bid }
                let cPost = apiService.collabPosts.first { $0.beacon_id == bid }
                let target = HighlightTarget(
                    beaconId: bid,
                    userName: pPos?.user_name ?? prof?.user_name ?? cPost?.user_name,
                    x: pPos?.estimated_x,
                    y: pPos?.estimated_y
                )
                UserDetailSheet(
                    userName: pPos?.user_name ?? prof?.user_name ?? cPost?.user_name,
                    department: pPos?.department ?? prof?.department,
                    jobTitle: pPos?.job_title ?? prof?.job_title,
                    profileImage: cPost?.profile_image ?? pPos?.profile_image ?? prof?.profile_image,
                    status: pPos?.status,
                    zone: nil,
                    matchReason: nil,
                    skills: prof?.skills,
                    hobbies: prof?.hobbies,
                    highlightTarget: target,
                    onHighlightUser: { ht in
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onHighlightUser?(ht)
                            onDismiss()
                        }
                    }
                )
            }
        }
    }

    // MARK: - Post Header
    private var postHeaderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: postTypeIcon(post.post_type))
                    .foregroundColor(postTypeColor(post.post_type))
                Text(postTypeLabel(post.post_type))
                    .font(.caption.weight(.medium))
                    .foregroundColor(postTypeColor(post.post_type))
                Spacer()
                if isClosed {
                    Text("クローズ済み")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            Text(post.title)
                .font(.headline)
                .foregroundColor(.white)
            HStack(spacing: 8) {
                detailAvatarWithStatus(post.profile_image, name: post.user_name, beaconId: post.beacon_id, size: 28)
                    .onTapGesture { highlightUser(beaconId: post.beacon_id, name: post.user_name) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.user_name ?? "匿名")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                    if let dept = apiService.persons.first(where: { $0.beacon_id == post.beacon_id })?.department, !dept.isEmpty {
                        Text(dept)
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                Spacer()
                if let date = post.created_at {
                    Text(date)
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
        }
    }

    // MARK: - Responses
    private var responsesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("応答 (\(responses.count))")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)

            if responses.isEmpty {
                Text("まだ応答はありません")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.vertical, 8)
            }

            ForEach(responses) { resp in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        detailAvatarWithStatus(resp.profile_image, name: resp.user_name, beaconId: resp.beacon_id, size: 22)
                            .onTapGesture { highlightUser(beaconId: resp.beacon_id, name: resp.user_name) }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(resp.user_name ?? "匿名")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white)
                            if let dept = apiService.persons.first(where: { $0.beacon_id == resp.beacon_id })?.department, !dept.isEmpty {
                                Text(dept)
                                    .font(.system(size: 9))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                        }
                        Spacer()
                        if let date = resp.created_at {
                            Text(String(date.prefix(16)))
                                .font(.system(size: 9))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                    if let msg = resp.message, !msg.isEmpty {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.leading, 28)
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Reply Input
    private var replyInputSection: some View {
        VStack(spacing: 8) {
            Divider().background(Color.gray.opacity(0.3))
            HStack(spacing: 8) {
                TextField("メッセージを入力...", text: $newMessage, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button {
                    guard !newMessage.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    isSending = true
                    Task {
                        let _ = await apiService.respondToCollabPost(
                            postId: post.id,
                            beaconId: beaconId,
                            userName: userName,
                            message: newMessage
                        )
                        responses = await apiService.fetchCollabResponses(postId: post.id)
                        newMessage = ""
                        isSending = false
                    }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(newMessage.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : AppTheme.accent)
                }
                .disabled(isSending || newMessage.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func detailAvatar(_ imageURL: String?, name: String?, size: CGFloat) -> some View {
        Group {
            if let urlStr = imageURL, !urlStr.isEmpty,
               let url = URL(string: ServerConfig.baseURL + urlStr) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    detailAvatarPlaceholder(name: name, size: size)
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                detailAvatarPlaceholder(name: name, size: size)
            }
        }
    }

    private func detailAvatarPlaceholder(name: String?, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(AppTheme.accent.opacity(0.3))
            Text(String((name ?? "?").prefix(1)))
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }

    private func detailAvatarWithStatus(_ imageURL: String?, name: String?, beaconId bid: String, size: CGFloat) -> some View {
        let personPos = apiService.persons.first { $0.beacon_id == bid }
        return ZStack(alignment: .bottomTrailing) {
            detailAvatar(imageURL, name: name, size: size)
            Circle()
                .fill(profileStatusColor(personPos?.status))
                .frame(width: size * 0.32, height: size * 0.32)
                .overlay(Circle().stroke(AppTheme.background, lineWidth: 1.5))
                .offset(x: 2, y: 2)
        }
    }

    private func highlightUser(beaconId bid: String, name: String?) {
        detailTargetBeaconId = bid
        showUserDetail = true
    }

    private func postTypeIcon(_ type: String) -> String {
        switch type {
        case "help_wanted": return "questionmark.circle"
        case "reviewer_needed": return "eye.circle"
        case "pair_programming": return "person.2"
        case "question": return "bubble.left.and.bubble.right"
        case "offer": return "hand.raised"
        default: return "doc.text"
        }
    }

    private func postTypeColor(_ type: String) -> Color {
        switch type {
        case "help_wanted": return .orange
        case "reviewer_needed": return .purple
        case "pair_programming": return .cyan
        case "question": return .yellow
        case "offer": return .green
        default: return .gray
        }
    }

    private func postTypeLabel(_ type: String) -> String {
        switch type {
        case "help_wanted": return "助けを求む"
        case "reviewer_needed": return "レビュー依頼"
        case "pair_programming": return "ペアプロ"
        case "question": return "質問"
        case "offer": return "お手伝い"
        default: return type
        }
    }
}

// MARK: - FlowLayout (horizontal wrapping)
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }
        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

// MARK: - New Collaboration Post Sheet
struct NewCollabPostSheet: View {
    @ObservedObject var apiService: APIService
    let beaconId: String
    @Binding var isPresented: Bool
    @State private var title = ""
    @State private var description = ""
    @State private var requiredSkills = ""
    @State private var postType = "help_wanted"
    @AppStorage(UserDefaultsConfig.Keys.userName) private var userName = ""

    private let postTypes: [(String, String)] = [
        ("help_wanted", "助けを求む"),
        ("reviewer_needed", "レビュー依頼"),
        ("pair_programming", "ペアプロ"),
        ("question", "質問"),
        ("offer", "お手伝い")
    ]

    var body: some View {
        NavigationView {
            Form {
                Section("投稿タイプ") {
                    Picker("タイプ", selection: $postType) {
                        ForEach(postTypes, id: \.0) { type in
                            Text(type.1).tag(type.0)
                        }
                    }
                }
                Section("内容") {
                    TextField("タイトル", text: $title)
                    TextField("詳細説明", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("必要なスキル (カンマ区切り)", text: $requiredSkills)
                }
            }
            .navigationTitle("新規投稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("投稿") {
                        Task {
                            let _ = await apiService.createCollabPost(
                                beaconId: beaconId,
                                userName: userName,
                                postType: postType,
                                title: title,
                                description: description,
                                requiredSkills: requiredSkills
                            )
                            await apiService.fetchCollabPosts()
                            isPresented = false
                        }
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}

// MARK: - 共通ユーザー詳細シート
struct UserDetailSheet: View {
    let userName: String?
    let department: String?
    let jobTitle: String?
    let profileImage: String?
    let status: String?
    let zone: String?
    let matchReason: String?
    let skills: String?
    let hobbies: String?
    var highlightTarget: HighlightTarget? = nil
    var onHighlightUser: ((HighlightTarget) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // アバター
                    userAvatar
                        .padding(.top, 16)

                    // 名前・部署・職種
                    VStack(spacing: 4) {
                        Text(userName ?? "Unknown")
                            .font(.title3.weight(.bold))
                            .foregroundColor(AppTheme.textPrimary)
                        if let dept = department, !dept.isEmpty {
                            Text(dept)
                                .font(.subheadline)
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        if let job = jobTitle, !job.isEmpty {
                            Text(job)
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }

                    // ステータス
                    if let s = status, !s.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(statusColor)
                            Text(statusLabel)
                                .font(.caption)
                                .foregroundColor(AppTheme.textPrimary)
                        }
                    }

                    // 位置情報
                    if let z = zone, !z.isEmpty {
                        detailRow(icon: "mappin.and.ellipse", label: "現在エリア", value: z)
                    } else {
                        detailRow(icon: "mappin.slash", label: "現在エリア", value: "位置情報なし")
                    }

                    // 位置を表示ボタン（位置情報がある場合のみ）
                    if let target = highlightTarget, target.x != nil, target.y != nil, let action = onHighlightUser {
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                action(target)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "scope")
                                Text("ヒートマップで位置を表示")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(AppTheme.accent)
                            .cornerRadius(8)
                        }
                        .padding(.horizontal, 16)
                    }

                    // 共通点
                    if let reason = matchReason, !reason.isEmpty {
                        CardView {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "sparkles")
                                        .foregroundColor(.yellow)
                                    Text("共通点")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(AppTheme.accent)
                                }
                                ForEach(reason.components(separatedBy: ","), id: \.self) { item in
                                    let trimmed = item.trimmingCharacters(in: .whitespaces)
                                    if !trimmed.isEmpty {
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(AppTheme.accent)
                                                .frame(width: 4, height: 4)
                                            Text(formatMatchReason(trimmed))
                                                .font(.caption)
                                                .foregroundColor(AppTheme.textPrimary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // スキル
                    if let skills = skills, !skills.isEmpty {
                        CardView {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "star")
                                        .foregroundColor(AppTheme.accent)
                                    Text("スキル")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(AppTheme.accent)
                                }
                                tagFlow(items: skills.components(separatedBy: ","))
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // 趣味
                    if let hobbies = hobbies, !hobbies.isEmpty {
                        CardView {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "heart")
                                        .foregroundColor(.pink)
                                    Text("趣味")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(AppTheme.accent)
                                }
                                tagFlow(items: hobbies.components(separatedBy: ","))
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    Spacer(minLength: 40)
                }
            }
            .background(AppTheme.background)
            .navigationTitle("ユーザー情報")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(AppTheme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var userAvatar: some View {
        Group {
            if let imgPath = profileImage,
               let url = URL(string: ServerConfig.baseURL + imgPath) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    avatarPlaceholder
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())
                .overlay(Circle().stroke(AppTheme.accent, lineWidth: 2))
            } else {
                avatarPlaceholder
            }
        }
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(AppTheme.accent.opacity(0.3))
                .frame(width: 80, height: 80)
            Text(String((userName ?? "?").prefix(1)))
                .font(.title.weight(.bold))
                .foregroundColor(.white)
        }
        .overlay(Circle().stroke(AppTheme.accent, lineWidth: 2))
    }

    private var statusColor: Color {
        switch status {
        case "available": return .green
        case "busy": return .red
        case "meeting": return .orange
        case "break": return .blue
        default: return .gray
        }
    }

    private var statusLabel: String {
        switch status {
        case "available": return "空き"
        case "busy": return "忙しい"
        case "meeting": return "会議中"
        case "break": return "休憩中"
        default: return "不明"
        }
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(AppTheme.accent)
                .frame(width: 20)
            Text(label)
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundColor(AppTheme.textPrimary)
        }
        .padding(.horizontal, 24)
    }

    private func formatMatchReason(_ item: String) -> String {
        if item.hasPrefix("skills:") {
            return "スキル: " + item.replacingOccurrences(of: "skills:", with: "")
        } else if item.hasPrefix("hobbies:") {
            return "趣味: " + item.replacingOccurrences(of: "hobbies:", with: "")
        }
        return item
    }

    private func tagFlow(items: [String]) -> some View {
        let tags = items.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.accent.opacity(0.15))
                    .cornerRadius(4)
            }
        }
    }
}

// MARK: - Feature 4: Lunch Match
struct LunchMatchSection: View {
    @ObservedObject var apiService: APIService
    let beaconId: String
    var onHighlightUser: ((HighlightTarget) -> Void)? = nil
    @State private var lunchAvailable: Bool = false
    @State private var matchOnSkills: Bool = true
    @State private var matchOnHobbies: Bool = true
    @State private var showSettings: Bool = false
    @State private var generateMessage: String? = nil
    @State private var isGenerating: Bool = false
    @State private var showPartnerDetail: Bool = false

    var body: some View {
        DashboardCard(title: "ランチ・コーヒーマッチ") {
            // Availability toggle
            HStack {
                Image(systemName: lunchAvailable ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .foregroundColor(lunchAvailable ? .green : .gray)
                    .font(.caption)
                Text("ランチ参加可能")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white)
                Spacer()
                Toggle("", isOn: $lunchAvailable)
                    .labelsHidden()
                    .tint(.green)
                    .onChange(of: lunchAvailable) { _ in saveAvailability() }
            }
            .padding(8)
            .background(lunchAvailable ? Color.green.opacity(0.08) : Color.black.opacity(0.1))
            .cornerRadius(6)

            // Settings toggle
            Button { showSettings.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10))
                    Text("マッチング条件")
                        .font(.system(size: 10))
                    Spacer()
                    Image(systemName: showSettings ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                }
                .foregroundColor(AppTheme.textSecondary)
            }

            if showSettings {
                VStack(spacing: 6) {
                    HStack {
                        Text("スキルで合わせる")
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                        Spacer()
                        Toggle("", isOn: $matchOnSkills)
                            .labelsHidden()
                            .tint(AppTheme.accent)
                            .onChange(of: matchOnSkills) { _ in saveAvailability() }
                    }
                    HStack {
                        Text("趣味で合わせる")
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                        Spacer()
                        Toggle("", isOn: $matchOnHobbies)
                            .labelsHidden()
                            .tint(AppTheme.accent)
                            .onChange(of: matchOnHobbies) { _ in saveAvailability() }
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.1))
                .cornerRadius(6)
            }

            // Today's match
            if let match = apiService.todaysLunchMatch {
                // Today's match card
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        lunchAvatarWithStatus(match.partner.profile_image, name: match.partner.user_name, beaconId: match.partner.beacon_id)
                            .contentShape(Circle())
                            .onTapGesture {
                                // 位置あり → ハイライト、位置なし → プロフィール
                                if let pos = match.partner.position, let x = pos.x, let y = pos.y {
                                    onHighlightUser?(HighlightTarget(
                                        beaconId: match.partner.beacon_id,
                                        userName: match.partner.user_name,
                                        x: x, y: y
                                    ))
                                } else {
                                    showPartnerDetail = true
                                }
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(match.partner.user_name ?? "Unknown")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white)
                            Text(match.partner.department ?? "")
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .onTapGesture {
                            showPartnerDetail = true
                        }
                        Spacer()
                        lunchStatusBadge(match.status)
                    }
                    if let reason = match.match_reason, !reason.isEmpty {
                        HStack {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                            Text(reason)
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textSecondary)
                            Spacer()
                        }
                    }
                    if match.status == "pending" {
                        HStack(spacing: 12) {
                            Button(action: { respondToMatch("accept") }) {
                                HStack {
                                    Image(systemName: "checkmark")
                                    Text("承諾")
                                }
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.green)
                                .cornerRadius(6)
                            }
                            Button(action: { respondToMatch("decline") }) {
                                HStack {
                                    Image(systemName: "xmark")
                                    Text("辞退")
                                }
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.7))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
                .padding(10)
                .background(Color.black.opacity(0.15))
                .cornerRadius(8)
            } else {
                VStack(spacing: 8) {
                    Text("今日のマッチはまだありません")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                    Button(action: {
                        isGenerating = true
                        generateMessage = nil
                        Task {
                            let (_, msg) = await apiService.generateLunchMatches()
                            await apiService.fetchTodaysLunchMatch(beaconId: beaconId)
                            if apiService.todaysLunchMatch == nil {
                                generateMessage = msg ?? "マッチを生成できませんでした"
                            }
                            isGenerating = false
                        }
                    }) {
                        HStack {
                            if isGenerating {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(.white)
                            } else {
                                Image(systemName: "shuffle")
                            }
                            Text("マッチを生成")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(isGenerating ? Color.gray : AppTheme.accent)
                        .cornerRadius(6)
                    }
                    .disabled(isGenerating)
                    if let msg = generateMessage {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 10))
                            Text(msg)
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.orange)
                        .padding(6)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(4)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .onAppear {
            Task {
                async let availTask: () = apiService.fetchUserAvailability(beaconId: beaconId)
                async let lunchTask: () = apiService.fetchTodaysLunchMatch(beaconId: beaconId)
                _ = await (availTask, lunchTask)
                if let avail = apiService.userAvailability {
                    lunchAvailable = avail.lunch_available ?? false
                    matchOnSkills = avail.match_on_skills ?? true
                    matchOnHobbies = avail.match_on_hobbies ?? true
                }
            }
        }
        .sheet(isPresented: $showPartnerDetail) {
            if let match = apiService.todaysLunchMatch {
                let personPos = apiService.persons.first { $0.beacon_id == match.partner.beacon_id }
                let profile = apiService.profiles.first { $0.beacon_id == match.partner.beacon_id }
                let target = HighlightTarget(
                    beaconId: match.partner.beacon_id,
                    userName: match.partner.user_name,
                    x: match.partner.position?.x,
                    y: match.partner.position?.y
                )
                UserDetailSheet(
                    userName: match.partner.user_name,
                    department: match.partner.department ?? personPos?.department,
                    jobTitle: match.partner.job_title ?? personPos?.job_title,
                    profileImage: match.partner.profile_image ?? personPos?.profile_image,
                    status: personPos?.status,
                    zone: match.partner.position?.zone,
                    matchReason: match.match_reason,
                    skills: match.partner.skills ?? profile?.skills,
                    hobbies: match.partner.hobbies ?? profile?.hobbies,
                    highlightTarget: target,
                    onHighlightUser: onHighlightUser
                )
            }
        }
    }

    private func respondToMatch(_ action: String) {
        guard let match = apiService.todaysLunchMatch else { return }
        Task {
            let _ = await apiService.respondToLunchMatch(matchId: match.id, beaconId: beaconId, action: action)
            await apiService.fetchTodaysLunchMatch(beaconId: beaconId)
        }
    }

    private func saveAvailability() {
        let avail = UserAvailability(
            beacon_id: beaconId,
            nearby_notify_enabled: apiService.userAvailability?.nearby_notify_enabled,
            notify_radius_mm: apiService.userAvailability?.notify_radius_mm,
            lunch_available: lunchAvailable,
            match_on_skills: matchOnSkills,
            match_on_hobbies: matchOnHobbies
        )
        Task { let _ = await apiService.updateUserAvailability(avail) }
    }

    private func lunchStatusBadge(_ status: String) -> some View {
        let label: String = {
            switch status {
            case "accepted": return "承諾済"
            case "declined": return "辞退"
            case "completed": return "完了"
            default: return "未回答"
            }
        }()
        let color: Color = {
            switch status {
            case "accepted": return .green
            case "declined": return .red
            default: return .orange
            }
        }()
        return Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .cornerRadius(4)
    }

    private func lunchAvatarWithStatus(_ imagePath: String?, name: String?, beaconId: String) -> some View {
        let personStatus = apiService.persons.first { $0.beacon_id == beaconId }?.status
        return ZStack(alignment: .bottomTrailing) {
            lunchAvatar(imagePath, name: name)
            Circle()
                .fill(profileStatusColor(personStatus))
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(AppTheme.background, lineWidth: 1.5))
                .offset(x: 2, y: 2)
        }
    }

    private func lunchAvatar(_ imagePath: String?, name: String?) -> some View {
        Group {
            if let imgPath = imagePath,
               let url = URL(string: ServerConfig.baseURL + imgPath) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    lunchAvatarPlaceholder(name: name)
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            } else {
                lunchAvatarPlaceholder(name: name)
            }
        }
    }

    private func lunchAvatarPlaceholder(name: String?) -> some View {
        ZStack {
            Circle().fill(AppTheme.accent.opacity(0.3))
            Text(String((name ?? "?").prefix(1)))
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white)
        }
        .frame(width: 40, height: 40)
    }
}

// MARK: - Feature 5: Interaction History
struct InteractionSection: View {
    @ObservedObject var apiService: APIService
    let beaconId: String
    @State private var selectedHours: Int = 168

    private let periodOptions: [(label: String, hours: Int)] = [
        ("12時間", 12), ("24時間", 24), ("3日間", 72), ("7日間", 168)
    ]

    var body: some View {
        DashboardCard(title: "交流分析") {
            // My interaction summary
            if let my = apiService.myInteractions {
                HStack(spacing: 16) {
                    interactionStatBox("交流人数", "\(my.total_unique_people ?? 0)人")
                    interactionStatBox("最活発ゾーン", my.most_active_zone ?? "-")
                }

                if let contacts = my.frequent_contacts, !contacts.isEmpty {
                    Text("よく交流する人")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppTheme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    ForEach(contacts.prefix(5)) { contact in
                        HStack {
                            Text(contact.user_name ?? String(contact.beacon_id.prefix(8)))
                                .font(.caption)
                                .foregroundColor(.white)
                            Text(contact.department ?? "")
                                .font(.system(size: 9))
                                .foregroundColor(AppTheme.textSecondary)
                            Spacer()
                            Text("\(contact.interaction_count)回")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppTheme.accent)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } else {
                Text("交流データを収集中...")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.vertical, 8)
            }

            // Department matrix (always visible)
            Text("部門間マトリクス")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(AppTheme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)

            // Period selector
            HStack(spacing: 4) {
                ForEach(periodOptions, id: \.hours) { option in
                    Button(action: {
                        selectedHours = option.hours
                        Task { await apiService.fetchInteractionStats(hours: option.hours) }
                    }) {
                        Text(option.label)
                            .font(.system(size: 9, weight: selectedHours == option.hours ? .bold : .regular))
                            .foregroundColor(selectedHours == option.hours ? .white : AppTheme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(selectedHours == option.hours ? AppTheme.accent : Color.white.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
            .padding(.bottom, 4)

            if let stats = apiService.interactionStats {
                departmentMatrixView(stats)

                // Suggestions
                if let suggestions = stats.suggestions, !suggestions.isEmpty {
                    ForEach(suggestions) { suggestion in
                        HStack(spacing: 4) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                            Text(suggestion.suggestion)
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .padding(6)
                        .background(Color.yellow.opacity(0.05))
                        .cornerRadius(4)
                    }
                }
            } else {
                Text("交流データを収集中...")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.vertical, 8)
            }
        }
        .onAppear {
            if apiService.myInteractions == nil || apiService.interactionStats == nil {
                Task {
                    async let a: () = apiService.fetchMyInteractions(beaconId: beaconId)
                    async let b: () = apiService.fetchInteractionStats()
                    _ = await (a, b)
                }
            }
        }
    }

    private func interactionStatBox(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundColor(AppTheme.accent)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color.black.opacity(0.15))
        .cornerRadius(6)
    }

    @ViewBuilder
    private func departmentMatrixView(_ stats: InteractionStats) -> some View {
        if let matrix = stats.department_matrix {
            // Collect all department names from both top-level and nested keys
            let allDepts: Set<String> = {
                var s = Set<String>()
                for (d1, innerMap) in matrix {
                    s.insert(d1)
                    for d2 in innerMap.keys { s.insert(d2) }
                }
                return s
            }()
            let depts = allDepts.sorted()
            VStack(spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    Text("")
                        .frame(width: 56, alignment: .leading)
                    ForEach(depts, id: \.self) { d in
                        Text(String(d.prefix(4)))
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                // Data rows
                ForEach(depts, id: \.self) { rowDept in
                    HStack(spacing: 0) {
                        Text(String(rowDept.prefix(6)))
                            .font(.system(size: 8))
                            .foregroundColor(AppTheme.textSecondary)
                            .frame(width: 56, alignment: .leading)
                        ForEach(depts, id: \.self) { colDept in
                            let pair = [rowDept, colDept].sorted()
                            let count = matrix[pair[0]]?[pair[1]] ?? 0
                            Text("\(count)")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .background(matrixCellColor(count))
                        }
                    }
                    .frame(height: 22)
                }
            }
            .padding(6)
            .background(Color.black.opacity(0.1))
            .cornerRadius(6)
        }
    }

    private func matrixCellColor(_ count: Int) -> Color {
        if count == 0 { return Color.clear }
        let opacity = min(Double(count) / 50.0, 1.0)
        return AppTheme.accent.opacity(opacity * 0.4)
    }
}

// MARK: - ソーシャル機能ガイドシート
struct SocialGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0

    private let guides: [FeatureGuide] = [
        FeatureGuide(
            icon: "magnifyingglass.circle.fill",
            color: .blue,
            title: "スキルマッチング",
            subtitle: "必要なスキルを持つ人を探す",
            steps: [
                GuideStep(icon: "text.cursor", text: "検索バーに探したいスキルを入力します（例: Python、デザイン）"),
                GuideStep(icon: "list.bullet", text: "該当するスキルを持つユーザーが一覧で表示されます"),
                GuideStep(icon: "mappin.and.ellipse", text: "ユーザーをタップすると、ダッシュボードに切り替わり、マップ上でその人の位置がハイライトされます"),
                GuideStep(icon: "figure.walk", text: "直接会いに行って、スキルについて相談できます"),
            ]
        ),
        FeatureGuide(
            icon: "person.2.circle.fill",
            color: .green,
            title: "近くのマッチ",
            subtitle: "周囲にいる人との共通点を発見",
            steps: [
                GuideStep(icon: "location.fill", text: "あなたの現在位置から半径3m以内にいるユーザーを自動検出します"),
                GuideStep(icon: "sparkles", text: "共通するスキルや趣味がある場合、「skills:Python」のようにマッチ情報が表示されます"),
                GuideStep(icon: "hand.wave.fill", text: "近くにいる人の名前・部署・距離を見て、気軽に声をかけてみましょう"),
                GuideStep(icon: "arrow.triangle.2.circlepath", text: "位置情報はリアルタイムで自動更新されます"),
            ]
        ),
        FeatureGuide(
            icon: "rectangle.3.group.bubble.fill",
            color: .orange,
            title: "コラボレーションボード",
            subtitle: "助けを求めたり、手伝いを申し出る",
            steps: [
                GuideStep(icon: "plus.circle", text: "「投稿する」ボタンから、助けを求む・レビュー依頼・ペアプロ募集・質問・お手伝いを投稿できます"),
                GuideStep(icon: "line.3.horizontal.decrease.circle", text: "タイプ別フィルターや並べ替えで、探している投稿を見つけやすくできます"),
                GuideStep(icon: "bubble.left.and.bubble.right", text: "投稿をタップすると詳細を確認でき、メッセージを送って応答できます"),
                GuideStep(icon: "checkmark.circle", text: "自分の投稿は「解決済み」ボタンでクローズできます。ボードには直近12時間の投稿が表示されます"),
            ]
        ),
        FeatureGuide(
            icon: "cup.and.saucer.fill",
            color: .pink,
            title: "ランチ・コーヒーマッチ",
            subtitle: "新しい人とランチに行く",
            steps: [
                GuideStep(icon: "hand.thumbsup.fill", text: "「ランチ参加可能」をONにすると、マッチング対象になります"),
                GuideStep(icon: "shuffle", text: "趣味やスキルが合う相手、または違う部署の人と自動的にペアリングされます"),
                GuideStep(icon: "person.crop.circle.badge.checkmark", text: "マッチした相手のプロフィール・共通の趣味・現在位置が表示されます"),
                GuideStep(icon: "face.smiling", text: "「参加する」で承諾、「辞退する」で断れます。気軽にランチに誘い合いましょう"),
            ]
        ),
        FeatureGuide(
            icon: "chart.bar.xaxis",
            color: .purple,
            title: "交流分析",
            subtitle: "誰とどれくらい交流しているかを可視化",
            steps: [
                GuideStep(icon: "person.3.fill", text: "過去7日間に近くにいた人の数・よく一緒にいる人・活動ゾーンが表示されます"),
                GuideStep(icon: "square.grid.3x3.fill", text: "部署間マトリクスで、どの部署同士の交流が多い/少ないかがひと目で分かります"),
                GuideStep(icon: "lightbulb.fill", text: "交流の少ない部署ペアに対して、合同ランチやコラボの提案が自動生成されます"),
                GuideStep(icon: "chart.line.uptrend.xyaxis", text: "定期的に確認して、チーム間のコミュニケーション改善に活用してください"),
            ]
        ),
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Page indicator
                HStack(spacing: 6) {
                    ForEach(0..<guides.count, id: \.self) { i in
                        Circle()
                            .fill(i == currentPage ? guides[currentPage].color : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 8)

                // Pager
                TabView(selection: $currentPage) {
                    ForEach(0..<guides.count, id: \.self) { index in
                        guidePageView(guides[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Navigation buttons
                HStack {
                    if currentPage > 0 {
                        Button {
                            withAnimation { currentPage -= 1 }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("前へ")
                            }
                            .font(.subheadline)
                            .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                    Spacer()
                    if currentPage < guides.count - 1 {
                        Button {
                            withAnimation { currentPage += 1 }
                        } label: {
                            HStack(spacing: 4) {
                                Text("次へ")
                                Image(systemName: "chevron.right")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(guides[currentPage].color)
                        }
                    } else {
                        Button {
                            dismiss()
                        } label: {
                            Text("はじめる")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(guides[currentPage].color)
                                .cornerRadius(20)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("ソーシャル機能ガイド")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func guidePageView(_ guide: FeatureGuide) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Feature icon and title
                VStack(spacing: 10) {
                    Image(systemName: guide.icon)
                        .font(.system(size: 44))
                        .foregroundColor(guide.color)
                        .padding(16)
                        .background(guide.color.opacity(0.15))
                        .clipShape(Circle())

                    Text(guide.title)
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)

                    Text(guide.subtitle)
                        .font(.subheadline)
                        .foregroundColor(AppTheme.textSecondary)
                }
                .padding(.top, 8)

                // Steps
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            // Step number + connector line
                            VStack(spacing: 0) {
                                ZStack {
                                    Circle()
                                        .fill(guide.color.opacity(0.8))
                                        .frame(width: 28, height: 28)
                                    Text("\(index + 1)")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                if index < guide.steps.count - 1 {
                                    Rectangle()
                                        .fill(guide.color.opacity(0.2))
                                        .frame(width: 2)
                                        .frame(maxHeight: .infinity)
                                }
                            }
                            .frame(width: 28)

                            // Content
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: step.icon)
                                    .font(.system(size: 16))
                                    .foregroundColor(guide.color)
                                    .frame(width: 20)
                                Text(step.text)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(10)
                            .padding(.bottom, index < guide.steps.count - 1 ? 4 : 0)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 16)
        }
    }
}

private struct FeatureGuide {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let steps: [GuideStep]
}

private struct GuideStep {
    let icon: String
    let text: String
}

// MARK: - 共通ステータスランプカラー
// プロフィールのステータス: 取り込み可能(available)=緑, 取り込み中(busy)=赤, 会議中(meeting)=オレンジ, 休憩中(break)=黄
private func profileStatusColor(_ status: String?) -> Color {
    switch status {
    case "available": return .green    // 取り込み可能
    case "busy":      return .red      // 取り込み中
    case "meeting":   return .orange   // 会議中
    case "break":     return .yellow   // 休憩中
    default:          return .gray     // 不明・オフライン
    }
}
