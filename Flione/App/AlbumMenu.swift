import AppKit

extension AppEnvironment {
    /// AppKit 右鍵選單中與專輯相關的共用項目：喜愛、加入 playlist。Album Wall 與 Library 共用
    func albumMenuItems(for album: Album) -> [NSMenuItem] {
        let favorite = ClosureMenuItem(favorites.contains(album.id) ? "Remove from Favorites" : "Add to Favorites") { [weak self] in
            self?.favorites.toggle(album.id)
        }

        let playlistsItem = NSMenuItem(title: String(localized: "Add to Playlist"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(ClosureMenuItem("New Playlist…") { [weak self] in
            Task { @MainActor in self?.newPlaylistTracks = (try? await self?.repository?.tracks(inAlbum: album.id)) ?? [] }
        })
        if !playlists.playlists.isEmpty { submenu.addItem(.separator()) }
        for playlist in playlists.playlists {
            submenu.addItem(ClosureMenuItem(verbatim: playlist.name) { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    let tracks = (try? await self.repository?.tracks(inAlbum: album.id)) ?? []
                    await self.playlists.add(tracks, to: playlist)
                }
            })
        }
        playlistsItem.submenu = submenu
        return [.separator(), favorite, playlistsItem]
    }
}
