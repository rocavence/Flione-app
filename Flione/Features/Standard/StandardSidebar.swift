import SwiftUI

/// Standard mode 左側導覽（Flione：Surface 1 面板，選取項目用 Surface Active 加一點 Flione Blue 邊）
struct StandardSidebar: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(StandardRouter.self) private var router

    var body: some View {
        VStack(spacing: 0) {
            navigation
            SidebarProfile()
        }
        .frame(width: 220)
        // 半透明：透出底下內容頁的背景光暈（D27）
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                FlioneColor.panel.opacity(0.3)
            }
        }
        // 側欄的框線都壓淡，只留輪廓（使用者要求不要明顯）
        .overlay(alignment: .trailing) { FlioneColor.hairline.opacity(0.25).frame(width: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sidebar")
    }

    private var navigation: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                item("Home", icon: .home, tab: .home)
                SidebarRow(title: "Search", icon: .search, isSelected: false) { app.isSearchPresented = true }

                header("Music")
                item("Albums", icon: .cd, tab: .library(.albums))
                item("Artists", icon: .user, tab: .library(.artists))
                item("Songs", icon: .musicNote, tab: .library(.songs))
                // YouTube Music 不提供曲風
                if app.source != .youtube { item("Genres", icon: .layers, tab: .library(.genres)) }
                item("Playlists", icon: .playlist2, tab: .library(.playlists))

                header("Smart")
                item("Discover", icon: .starSparkle, tab: .discover)
                item("Recently Added", icon: .clock, tab: .recentlyAdded)
                item("Favorites", icon: .heart, tab: .library(.favorites))

                if !app.playlists.playlists.isEmpty {
                    header("Playlists")
                    ForEach(app.playlists.playlists) { playlist in
                        PlaylistSidebarRow(playlist: playlist, isSelected: router.path.last == .playlist(playlist)) {
                            router.open(.playlist(playlist))
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.s12)
            // 頂部留給視窗紅綠燈
            .padding(.top, 52)
            .padding(.bottom, Spacing.s16)
        }
    }

    private func item(_ title: LocalizedStringResource, icon: Reicon, tab: StandardTab) -> some View {
        SidebarRow(title: title, icon: icon, isSelected: router.tab == tab && router.path.isEmpty) {
            if router.tab == tab { router.popToRoot() } else { router.tab = tab }
        }
    }

    private func header(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .flioneFont(.caption)
            .foregroundStyle(FlioneColor.faint)
            .padding(.horizontal, Spacing.s12)
            .padding(.top, Spacing.s20)
            .padding(.bottom, Spacing.s4)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct SidebarRow: View {
    let title: LocalizedStringResource
    let icon: Reicon
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s12) {
                FlioneIcon(icon, weight: isSelected ? .filled : .outline, size: .standard)
                    .foregroundStyle(isSelected ? FlioneColor.ink : FlioneColor.muted)
                // 西文、葡文的名稱較長（「Adicionados recentemente」）：維持一行，必要時稍微縮小
                Text(title)
                    .flioneFont(isSelected ? .bodyEmphasis : .body)
                    .foregroundStyle(isSelected ? FlioneColor.ink : FlioneColor.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.s12)
            .frame(height: 34)
            .background(background, in: RoundedRectangle(cornerRadius: Radius.ui, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Radius.ui, style: .continuous)
                        .strokeBorder(FlioneColor.accent.opacity(0.08), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        if isSelected { return FlioneColor.active }
        return hovering ? FlioneColor.glassHighlight : .clear
    }
}

private struct PlaylistSidebarRow: View {
    let playlist: Playlist
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s12) {
                ArtworkView(artwork: playlist.artwork, cornerRadius: Radius.small, elevation: .none, fallbackTitle: nil)
                    .frame(width: 24, height: 24)
                Text(playlist.name)
                    .flioneFont(.body)
                    .foregroundStyle(isSelected ? FlioneColor.ink : FlioneColor.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.s12)
            .frame(height: 34)
            .background(isSelected ? FlioneColor.active : (hovering ? FlioneColor.glassHighlight : .clear),
                        in: RoundedRectangle(cornerRadius: Radius.ui, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(playlist.name), playlist")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 側欄底部：登入者頭像、名稱與 server；點一下打開帳號選單（含設定入口，做法參考 Kaset 的 SidebarProfileView）
private struct SidebarProfile: View {
    @Environment(AppEnvironment.self) private var app
    @State private var showsAccount = false
    @State private var hovering = false

    var body: some View {
        if let session = app.session {
            Button { showsAccount = true } label: {
                HStack(spacing: Spacing.s8) {
                    UserAvatar(session: session, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.userName)
                            .flioneFont(.bodyEmphasis)
                            .foregroundStyle(FlioneColor.ink)
                        Text(session.serverName)
                            .flioneFont(.caption)
                            .foregroundStyle(FlioneColor.muted)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    FlioneIcon(.chevronUp, size: .compact)
                        .foregroundStyle(FlioneColor.faint)
                }
                // 與上方選單項目相同：外層 12 ＋ 內層 12，頭像與歌單縮圖對齊在 24pt
                .padding(.horizontal, Spacing.s12)
                .frame(height: 48)
                .background(hovering ? FlioneColor.glassHighlight : .clear, in: RoundedRectangle(cornerRadius: Radius.ui, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Motion.micro, value: hovering)
            .accessibilityLabel("\(session.userName) on \(session.serverName)")
            .accessibilityHint("Shows account options")
            .popover(isPresented: $showsAccount, arrowEdge: .top) {
                AccountPopover(session: session) { showsAccount = false }
                    .environment(app)
            }
            .padding(.horizontal, Spacing.s12)
            .padding(.vertical, Spacing.s8)
            .overlay(alignment: .top) { FlioneColor.hairline.opacity(0.25).frame(height: 1) }
        }
    }
}

/// 帳號選單：server 資訊、重新整理音樂庫、設定、登出
private struct AccountPopover: View {
    let session: JellyfinSession
    let dismiss: () -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.s12) {
                UserAvatar(session: session, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.userName).flioneFont(.subheading).foregroundStyle(FlioneColor.ink)
                    Text(session.serverURL.host() ?? session.serverURL.absoluteString)
                        .flioneFont(.caption).foregroundStyle(FlioneColor.muted)
                    Text("\(app.library.albums.count) albums").flioneFont(.caption).foregroundStyle(FlioneColor.faint)
                }
                .lineLimit(1)
            }
            .padding(Spacing.s12)
            Divider().padding(.vertical, Spacing.s4)
            row("Refresh Library", icon: .refresh) {
                Task { await app.library.refresh() }
            }
            .disabled(app.library.state == .loading)
            row("Settings…", icon: .setting2) { app.isSettingsPresented = true }
            // 切換音樂來源（D39）：另一邊的登入保留
            let other: MusicSource = app.source == .youtube ? .jellyfin : .youtube
            row("Switch to \(other.title)", icon: .refresh) { Task { await app.switchSource(to: other) } }
            Divider().padding(.vertical, Spacing.s4)
            row("Sign Out", icon: .power, role: .destructive) { app.signOut() }
        }
        .padding(Spacing.s8)
        .frame(width: 260)
    }

    private func row(_ title: LocalizedStringResource, icon: Reicon, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        PopoverRow(title: title, icon: icon, destructive: role == .destructive) {
            dismiss()
            action()
        }
    }
}

private struct PopoverRow: View {
    let title: LocalizedStringResource
    let icon: Reicon
    let destructive: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s12) {
                FlioneIcon(icon, size: .compact)
                Text(title).flioneFont(.body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(destructive ? FlioneColor.danger : FlioneColor.ink)
            .padding(.horizontal, Spacing.s12)
            .frame(height: 32)
            .background(hovering && isEnabled ? FlioneColor.glassHighlight : .clear, in: RoundedRectangle(cornerRadius: Radius.ui, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovering = $0 }
    }
}

/// Jellyfin 使用者頭像；沒有設定頭像時顯示名字的第一個字
struct UserAvatar: View {
    let session: JellyfinSession
    let size: CGFloat

    var body: some View {
        AsyncImage(url: session.avatarURL(pixelSize: Int(size * 2))) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    FlioneColor.aurora
                    Text(session.userName.prefix(1).uppercased())
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(FlioneColor.hairline.opacity(0.3), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

extension JellyfinSession {
    /// 使用者頭像（Jellyfin 的使用者圖片不需要登入就能取得；沒有頭像時回 404）
    func avatarURL(pixelSize: Int) -> URL {
        if let avatar { return avatar }
        var components = URLComponents(url: serverURL.appending(path: "Users/\(userID)/Images/Primary"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "maxWidth", value: "\(pixelSize)"), URLQueryItem(name: "maxHeight", value: "\(pixelSize)")]
        return components.url!
    }
}
