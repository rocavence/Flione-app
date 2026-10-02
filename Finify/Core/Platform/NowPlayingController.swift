import AppKit
import MediaPlayer

/// macOS Now Playing（Control Center、鎖定畫面）與媒體鍵。
/// 媒體鍵在 macOS 經由 MPRemoteCommandCenter 傳入，不需要另外攔截鍵盤事件。
@MainActor
final class NowPlayingController {
    private let player: PlayerManager
    private let images: () -> ImagePipeline?
    private var artworkTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?

    init(player: PlayerManager, images: @escaping () -> ImagePipeline?) {
        self.player = player
        self.images = images
        registerCommands()
        observe()
    }

    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { if self?.player.isPlaying == false { self?.player.togglePlayPause() } }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { self?.player.seek(to: event.positionTime) }
            return .success
        }
    }

    /// 以 Observation 追蹤播放狀態，有變化時更新 Now Playing
    private func observe() {
        withObservationTracking {
            _ = player.currentTrack
            _ = player.isPlaying
            _ = player.duration
            _ = Int(player.currentTime / 5)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.observe()
            }
        }
    }

    private var lastTrackID: String?

    private func update() {
        let center = MPNowPlayingInfoCenter.default()
        guard let track = player.currentTrack else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var info = center.nowPlayingInfo ?? [:]
        if track.id != lastTrackID {
            info = [:]
            lastTrackID = track.id
            loadArtwork(for: track)
        }
        info[MPMediaItemPropertyTitle] = track.name
        info[MPMediaItemPropertyArtist] = track.artistName
        info[MPMediaItemPropertyAlbumTitle] = track.albumName
        info[MPMediaItemPropertyPlaybackDuration] = player.duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = player.isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        center.nowPlayingInfo = info
        center.playbackState = player.isPlaying ? .playing : .paused
    }

    private func loadArtwork(for track: Track) {
        artworkTask?.cancel()
        guard let ref = track.artwork, let images = images() else { return }
        artworkTask = Task {
            guard let cgImage = await images.image(ref, pixelSize: 600), !Task.isCancelled else { return }
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            let center = MPNowPlayingInfoCenter.default()
            var info = center.nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = artwork
            center.nowPlayingInfo = info
        }
    }
}
