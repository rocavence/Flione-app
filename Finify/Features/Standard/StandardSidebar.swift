import SwiftUI

/// Standard mode 左側導覽（Finity 設計：Deep Navy 面板，選取項目只用一點 Finity Blue）
struct StandardSidebar: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(StandardRouter.self) private var router

    var body: some View {
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
                SidebarRow(title: "Overflow", icon: .grid, isSelected: false) { app.mode = .overflow }

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
        .frame(width: 220)
        .background(FinifyColor.panel)
        .overlay(alignment: .trailing) { FinifyColor.hairline.frame(width: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sidebar")
    }

    private func item(_ title: String, icon: Reicon, tab: StandardTab) -> some View {
        SidebarRow(title: title, icon: icon, isSelected: router.tab == tab && router.path.isEmpty) {
            if router.tab == tab { router.popToRoot() } else { router.tab = tab }
        }
    }

    private func header(_ title: String) -> some View {
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
    let title: String
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
                        .strokeBorder(FinifyColor.accent.opacity(0.35), lineWidth: 1)
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
        if isSelected { return FinifyColor.accent.opacity(0.22) }
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
            .background(isSelected ? FinifyColor.accent.opacity(0.22) : (hovering ? FinifyColor.glassHighlight : .clear),
                        in: RoundedRectangle(cornerRadius: Radius.ui, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(playlist.name), playlist")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
