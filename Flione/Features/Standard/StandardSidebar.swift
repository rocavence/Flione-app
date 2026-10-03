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
                FinifyColor.panel.opacity(0.3)
            }
        }
        // 側欄的框線都壓淡，只留輪廓（使用者要求不要明顯）
        .overlay(alignment: .trailing) { FinifyColor.hairline.opacity(0.25).frame(width: 1) }
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
                item("Genres", icon: .layers, tab: .library(.genres))
                item("Playlists", icon: .playlist2, tab: .library(.playlists))

                header("Smart")
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
            .finifyFont(.caption)
            .foregroundStyle(FinifyColor.faint)
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
                FinifyIcon(icon, weight: isSelected ? .filled : .outline, size: .standard)
                    .foregroundStyle(isSelected ? FinifyColor.ink : FinifyColor.muted)
                Text(title)
                    .finifyFont(isSelected ? .bodyEmphasis : .body)
                    .foregroundStyle(isSelected ? FinifyColor.ink : FinifyColor.muted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.s12)
            .frame(height: 34)
            .background(background, in: RoundedRectangle(cornerRadius: Radius.ui, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Radius.ui, style: .continuous)
                        .strokeBorder(FinifyColor.accent.opacity(0.08), lineWidth: 1)
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
        if isSelected { return FinifyColor.active }
        return hovering ? FinifyColor.glassHighlight : .clear
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
                    .finifyFont(.body)
                    .foregroundStyle(isSelected ? FinifyColor.ink : FinifyColor.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.s12)
            .frame(height: 34)
            .background(isSelected ? FinifyColor.active : (hovering ? FinifyColor.glassHighlight : .clear),
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
                            .finifyFont(.bodyEmphasis)
                            .foregroundStyle(FinifyColor.ink)
                        Text(session.serverName)
                            .finifyFont(.caption)
                            .foregroundStyle(FinifyColor.muted)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    FinifyIcon(.chevronUp, size: .compact)
                        .foregroundStyle(FinifyColor.faint)
                }
                // 與上方選單項目相同：外層 12 ＋ 內層 12，頭像與歌單縮圖對齊在 24pt
                .padding(.horizontal, Spacing.s12)
                .frame(height: 48)
                .background(hovering ? FinifyColor.glassHighlight : .clear, in: RoundedRectangle(cornerRadius: Radius.ui, style: .continuous))
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
            .overlay(alignment: .top) { FinifyColor.hairline.opacity(0.25).frame(height: 1) }
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
                    Text(session.userName).finifyFont(.subheading).foregroundStyle(FinifyColor.ink)
                    Text(session.serverURL.host() ?? session.serverURL.absoluteString)
                        .finifyFont(.caption).foregroundStyle(FinifyColor.muted)
                    Text("\(app.library.albums.count) albums").finifyFont(.caption).foregroundStyle(FinifyColor.faint)
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
                FinifyIcon(icon, size: .compact)
                Text(title).finifyFont(.body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(destructive ? FinifyColor.danger : FinifyColor.ink)
            .padding(.horizontal, Spacing.s12)
            .frame(height: 32)
            .background(hovering && isEnabled ? FinifyColor.glassHighlight : .clear, in: RoundedRectangle(cornerRadius: Radius.ui, style: .continuous))
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
                    FinifyColor.aurora
                    Text(session.userName.prefix(1).uppercased())
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(FinifyColor.hairline.opacity(0.3), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

extension JellyfinSession {
    /// 使用者頭像（Jellyfin 的使用者圖片不需要登入就能取得；沒有頭像時回 404）
    func avatarURL(pixelSize: Int) -> URL {
        var components = URLComponents(url: serverURL.appending(path: "Users/\(userID)/Images/Primary"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "maxWidth", value: "\(pixelSize)"), URLQueryItem(name: "maxHeight", value: "\(pixelSize)")]
        return components.url!
    }
}
