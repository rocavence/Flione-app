import SwiftUI

/// 非同步資料的狀態。每個畫面都必須處理 loading / empty / error。
enum Loadable<Value> {
    case loading
    case loaded(Value)
    case failed
}

extension Loadable: Sendable where Value: Sendable {}

@MainActor @Observable
final class HomeViewModel {
    var recentlyPlayed: Loadable<[Album]> = .loading
    var recentlyAdded: Loadable<[Album]> = .loading
    var quickPicks: Loadable<[Album]> = .loading

    func load(_ repository: (any MusicRepository)?) async {
        guard let repository else { return }
        async let played = Self.fetch { try await repository.recentlyPlayed(limit: 12) }
        async let added = Self.fetch { try await repository.recentlyAdded(limit: 16) }
        async let picks = Self.fetch { try await repository.quickPicks(limit: 12) }
        (recentlyPlayed, recentlyAdded, quickPicks) = await (played, added, picks)
    }

    nonisolated private static func fetch(_ work: @Sendable () async throws -> [Album]) async -> Loadable<[Album]> {
        do { return .loaded(try await work()) } catch { return .failed }
    }
}

struct HomeView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(StandardRouter.self) private var router
    @State private var model = HomeViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s40) {
                Text(greeting)
                    .finifyFont(.title)
                    .foregroundStyle(FinifyColor.ink)
                    .padding(.top, Spacing.s32)

                if case .failed = model.recentlyAdded, case .failed = model.quickPicks {
                    MessageState(
                        title: "Can't reach your music server.",
                        message: "Your library will appear here as soon as the connection is back.",
                        icon: .wifiOff,
                        primary: ("Retry", { Task { await reload() } })
                    )
                } else {
                    shelf("Recently Played", model.recentlyPlayed, empty: "Albums you play will show up here.")
                    shelf("Recently Added", model.recentlyAdded, empty: "New albums on your server will show up here.")
                    shelf("Quick Picks", model.quickPicks, empty: nil, refresh: { Task { await reloadPicks() } })
                }
            }
            .padding(.horizontal, Spacing.s32)
            .padding(.bottom, Spacing.s48)
        }
        .task { await model.load(app.repository) }
        .onChange(of: app.reconnectCount) { Task { await reload() } }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        case 18..<23: "Good evening"
        default: "Late night listening"
        }
    }

    private func reload() async {
        model.recentlyPlayed = .loading
        model.recentlyAdded = .loading
        model.quickPicks = .loading
        await model.load(app.repository)
    }

    private func reloadPicks() async {
        guard let repository = app.repository else { return }
        if let picks = try? await repository.quickPicks(limit: 12) {
            withAnimation(Motion.ui) { model.quickPicks = .loaded(picks) }
        }
    }

    @ViewBuilder
    private func shelf(_ title: String, _ state: Loadable<[Album]>, empty: String?, refresh: (() -> Void)? = nil) -> some View {
        switch state {
        case .loaded(let albums) where albums.isEmpty:
            if let empty {
                VStack(alignment: .leading, spacing: Spacing.s16) {
                    SectionHeader(title: title)
                    Text(empty).finifyFont(.body).foregroundStyle(FinifyColor.muted)
                }
            }
        case .failed:
            EmptyView()
        default:
            VStack(alignment: .leading, spacing: Spacing.s16) {
                SectionHeader(title: title, action: refresh.map { ("Shuffle picks", $0) })
                AlbumShelf(state: state)
            }
        }
    }
}

/// 一列可橫向捲動的專輯
struct AlbumShelf: View {
    let state: Loadable<[Album]>
    var cardWidth: CGFloat = 168
    @Environment(AppEnvironment.self) private var app
    @Environment(StandardRouter.self) private var router

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: Spacing.s20) {
                switch state {
                case .loaded(let albums):
                    ForEach(albums) { album in
                        AlbumCard(album: album, onOpen: { router.openAlbum(album) }, onPlay: { play(album) })
                            .frame(width: cardWidth)
                    }
                default:
                    ForEach(0..<7, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: Spacing.s8) {
                            SkeletonBlock().aspectRatio(1, contentMode: .fit)
                            SkeletonBlock().frame(width: 120, height: 10)
                            SkeletonBlock().frame(width: 80, height: 8)
                        }
                        .frame(width: cardWidth)
                    }
                }
            }
            .padding(.vertical, Spacing.s8)
        }
        .scrollClipDisabled()
    }

    private func play(_ album: Album) {
        Task {
            guard let tracks = try? await app.repository?.tracks(inAlbum: album.id) else { return }
            app.player.play(tracks)
        }
    }
}
