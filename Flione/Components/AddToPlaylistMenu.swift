import SwiftUI

/// 右鍵選單中的「Add to Playlist ▸」。曲目以 closure 取得（專輯需要先載入曲目）。
struct AddToPlaylistMenu: View {
    let tracks: () async -> [Track]
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Menu("Add to Playlist") {
            Button("New Playlist…") {
                Task { app.newPlaylistTracks = await tracks() }
            }
            if !app.playlists.playlists.isEmpty { Divider() }
            ForEach(app.playlists.playlists) { playlist in
                Button(playlist.name) {
                    Task { await app.playlists.add(await tracks(), to: playlist) }
                }
            }
        }
    }
}

/// 建立 playlist 時輸入名稱
struct NewPlaylistPrompt: ViewModifier {
    @Environment(AppEnvironment.self) private var app
    @State private var name = ""

    func body(content: Content) -> some View {
        @Bindable var app = app
        content.alert("New Playlist", isPresented: Binding(
            get: { app.newPlaylistTracks != nil },
            set: { if !$0 { app.newPlaylistTracks = nil } }
        )) {
            TextField("Playlist name", text: $name)
            Button("Create") {
                let tracks = app.newPlaylistTracks ?? []
                let title = name.trimmingCharacters(in: .whitespaces).isEmpty ? "New Playlist" : name
                name = ""
                Task { _ = await app.playlists.create(name: title, tracks: tracks) }
            }
            Button("Cancel", role: .cancel) { name = "" }
        } message: {
            let count = app.newPlaylistTracks?.count ?? 0
            Text(count == 0 ? "Create an empty playlist." : "Create a playlist with \(count) songs.")
        }
    }
}
