import SwiftUI

/// Playlist 頁：播放、改名、刪除、拖曳排序、移除歌曲。每次編輯都以完整狀態儲存（D13）。
struct PlaylistView: View {
    let playlist: Playlist
    @Environment(AppEnvironment.self) private var app
    @Environment(StandardRouter.self) private var router
    @State private var tracks: Loadable<[Track]> = .loading
    @State private var name: String = ""
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var isConfirmingDelete = false
    @State private var dragging: Int?
    @State private var pendingCommit: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s32) {
                header
                trackList
            }
            .padding(Spacing.s32)
        }
        .background(alignment: .top) { AmbientWash(artwork: playlist.artwork ?? list.first?.artwork) }
        .task(id: playlist.id) {
            name = playlist.name
            await load()
        }
        .onChange(of: app.playlists.revision(of: playlist.id)) { Task { await load() } }
        .alert("Rename Playlist", isPresented: $isRenaming) {
            TextField("Playlist name", text: $draftName)
            Button("Rename") { rename(to: draftName) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(name)”?", isPresented: $isConfirmingDelete) {
            Button("Delete Playlist", role: .destructive) {
                Task { if await app.playlists.delete(playlist) { router.back() } }
            }
        } message: {
            Text("The playlist is removed from your music server. The songs stay in your library.")
        }
    }

    private var list: [Track] {
        if case .loaded(let list) = tracks { return list }
        return []
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: Spacing.s32) {
            ArtworkView(artwork: playlist.artwork ?? list.first?.artwork, elevation: .playing, fallbackTitle: name)
                .frame(width: 232, height: 232)
            VStack(alignment: .leading, spacing: Spacing.s12) {
                Text("Playlist").finifyFont(.micro).textCase(.uppercase).foregroundStyle(FinifyColor.muted)
                Text(name).finifyFont(.display).foregroundStyle(FinifyColor.ink).lineLimit(2).minimumScaleFactor(0.6)
                Text("\(list.count) songs · \(list.reduce(0) { $0 + $1.duration }.formattedDuration)")
                    .finifyFont(.body)
                    .foregroundStyle(FinifyColor.muted)
                HStack(spacing: Spacing.s8) {
                    FinifyButton(title: "Play", icon: .play, kind: .primary) { app.player.play(list) }
                        .disabled(list.isEmpty)
                    FinifyButton(title: "Shuffle", icon: .shuffle) { app.player.play(list, shuffled: true) }
                        .disabled(list.isEmpty)
                    FinifyIconButton(icon: .edit, label: "Rename playlist") {
                        draftName = name
                        isRenaming = true
                    }
                    FinifyIconButton(icon: .trash, label: "Delete playlist") { isConfirmingDelete = true }
                }
                .padding(.top, Spacing.s8)
            }
        }
    }

    @ViewBuilder
    private var trackList: some View {
        switch tracks {
        case .loading:
            VStack(spacing: Spacing.s8) { ForEach(0..<8, id: \.self) { _ in SkeletonBlock().frame(height: 44) } }
        case .failed:
            MessageState(title: "Can't load this playlist.", message: "Check your connection to the music server.", icon: .wifiOff,
                         primary: ("Retry", { Task { await load() } }))
        case .loaded(let list) where list.isEmpty:
            MessageState(title: "This playlist is empty.", message: "Right-click any song or album and choose Add to Playlist.", icon: .playlist)
        case .loaded(let list):
            VStack(spacing: 2) {
                ForEach(Array(list.enumerated()), id: \.offset) { index, track in
                    TrackRow(track: track, number: index + 1, showsArtwork: true, showsAlbum: true, onPlay: {
                        app.player.play(list, startAt: index)
                    }, onOpenArtist: { router.openArtist(id: track.artistID, name: track.artistName) },
                       extraMenu: [("Remove from Playlist", { remove(at: index) })])
                    .opacity(dragging == index ? 0.4 : 1)
                    .onDrag {
                        dragging = index
                        return NSItemProvider(object: String(index) as NSString)
                    }
                    .onDrop(of: [.text], delegate: PlaylistDropDelegate(target: index, dragging: $dragging, move: move, commit: commit))
                    .accessibilityAction(named: "Remove from Playlist") { remove(at: index) }
                }
            }
        }
    }

    private func load() async {
        guard let repository = app.repository else { return }
        do {
            let result = try await repository.playlistTracks(playlist.id)
            guard !Task.isCancelled else { return }
            tracks = .loaded(result)
        } catch {
            guard !Task.isCancelled else { return }
            tracks = .failed
        }
    }

    /// 拖曳中即時移動（只改畫面）
    private func move(from: Int, to: Int) {
        var list = self.list
        guard list.indices.contains(from), list.indices.contains(to) else { return }
        list.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
        withAnimation(Motion.micro) { tracks = .loaded(list) }
        pendingCommit?.cancel()
        pendingCommit = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            dragging = nil
            commit()
        }
    }

    /// 放開時才寫回 server
    private func commit() {
        pendingCommit?.cancel()
        pendingCommit = nil
        let list = self.list
        Task { _ = await app.playlists.save(playlist, name: name, tracks: list) }
    }

    private func remove(at index: Int) {
        var list = self.list
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        withAnimation(Motion.micro) { tracks = .loaded(list) }
        commit()
    }

    private func rename(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != name else { return }
        let old = name
        name = trimmed
        Task { if !(await app.playlists.save(playlist, name: trimmed, tracks: list)) { name = old } }
    }
}

private struct PlaylistDropDelegate: DropDelegate {
    let target: Int
    @Binding var dragging: Int?
    let move: (Int, Int) -> Void
    let commit: () -> Void

    func dropEntered(info: DropInfo) {
        guard let from = dragging, from != target else { return }
        move(from, target)
        dragging = target
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        commit()
        return true
    }
}
