import SwiftUI

/// 類型頁：該類型的所有專輯；Shuffle 從該類型隨機挑 200 首
struct GenreView: View {
    let genre: Genre
    @Environment(AppEnvironment.self) private var app
    @State private var albums: Loadable<[Album]> = .loading

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s32) {
                HStack(alignment: .bottom, spacing: Spacing.s32) {
                    ArtworkView(artwork: genre.artwork, elevation: .playing, fallbackTitle: genre.name)
                        .frame(width: 200, height: 200)
                    VStack(alignment: .leading, spacing: Spacing.s12) {
                        Text("Genre").finifyFont(.micro).textCase(.uppercase).foregroundStyle(FinifyColor.muted)
                        Text(genre.name).finifyFont(.display).foregroundStyle(FinifyColor.ink).lineLimit(2).minimumScaleFactor(0.6)
                        if case .loaded(let list) = albums {
                            Text("\(list.count) albums").finifyFont(.body).foregroundStyle(FinifyColor.muted)
                        }
                        FinifyButton(title: "Shuffle", icon: .shuffle, kind: .primary) {
                            Task {
                                if let tracks = try? await app.repository?.randomTracks(inGenre: genre.id, limit: 200) {
                                    app.player.play(tracks)
                                }
                            }
                        }
                        .padding(.top, Spacing.s8)
                    }
                }
                switch albums {
                case .loading:
                    AlbumGrid(albums: nil)
                case .failed:
                    MessageState(title: "Can't load this genre.", message: "Check your connection to the music server.", icon: .wifiOff,
                                 primary: ("Retry", { Task { await load() } }))
                case .loaded(let list) where list.isEmpty:
                    MessageState(title: "No albums in \(genre.name).", message: "Albums tagged with this genre on your server will show up here.")
                case .loaded(let list):
                    AlbumGrid(albums: list)
                }
            }
            .padding(Spacing.s32)
        }
        .background(alignment: .top) { AmbientWash(artwork: genre.artwork) }
        .task { await load() }
    }

    private func load() async {
        guard let repository = app.repository else { return }
        do { albums = .loaded(try await repository.albums(inGenre: genre.id)) } catch { albums = .failed }
    }
}
