import UniformTypeIdentifiers
import SwiftUI

/// 底部 mini player：封面、曲名、播放控制、進度、queue、音量。
struct PlayerBar: View {
    let onOpenAlbum: (String?) -> Void
    let onOpenArtist: (String?, String) -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let player = app.player
        HStack(spacing: Spacing.s16) {
            nowPlaying
                .frame(width: 280, alignment: .leading)
            Spacer(minLength: 0)
            VStack(spacing: Spacing.s4) {
                PlaybackControls()
                HStack(spacing: Spacing.s8) {
                    Text(player.currentTime.formattedDuration)
                        .frame(width: 44, alignment: .trailing)
                    ProgressBar(value: player.progress) { player.seek(to: $0 * player.duration) }
                        .accessibilityLabel("Playback position")
                    Text(player.duration.formattedDuration)
                        .frame(width: 44, alignment: .leading)
                }
                .finifyFont(.caption)
                .monospacedDigit()
                .foregroundStyle(FinifyColor.muted)
                .disabled(player.currentTrack == nil)
            }
            .frame(maxWidth: 520)
            Spacer(minLength: 0)
            HStack(spacing: Spacing.s8) {
                FinifyIconButton(icon: .microphone, label: "Lyrics", isActive: app.isLyricsPresented) {
                    app.isLyricsPresented.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
                FinifyIconButton(icon: .playlist, label: "Queue", isActive: app.isQueuePresented) {
                    app.isQueuePresented.toggle()
                }
                .keyboardShortcut("u", modifiers: [.command])
                FinifyIconButton(icon: .fullscreen, label: "Fullscreen player (⌃⌘F)") { app.enterFullscreenPlayer() }
                    .disabled(app.player.currentTrack == nil)
                VolumeControl()
            }
            .frame(width: 280, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.s16)
        .frame(height: 80)
        .background(FinifyColor.panel)
        .overlay(alignment: .top) { FinifyColor.hairline.frame(height: 1) }
    }

    @ViewBuilder
    private var nowPlaying: some View {
        if let track = app.player.currentTrack {
            HStack(spacing: Spacing.s12) {
                HStack(spacing: Spacing.s12) {
                    ArtworkView(artwork: track.artwork, elevation: .none)
                        .frame(width: 52, height: 52)
                        .onTapGesture { onOpenAlbum(track.albumID) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name)
                            .finifyFont(.bodyEmphasis)
                            .foregroundStyle(FinifyColor.ink)
                            .lineLimit(1)
                            .onTapGesture { onOpenAlbum(track.albumID) }
                        Text(track.artistName)
                            .finifyFont(.caption)
                            .foregroundStyle(FinifyColor.muted)
                            .lineLimit(1)
                            .onTapGesture { onOpenArtist(track.artistID, track.artistName) }
                    }
                }
                // 只合併封面與文字；愛心要保持為獨立按鈕，VoiceOver 才能操作
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Now playing: \(track.name) by \(track.artistName)")
                .accessibilityHint("Opens the album")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(.default) { onOpenAlbum(track.albumID) }
                FavoriteButton(itemID: track.id, name: track.name)
            }
        } else {
            HStack(spacing: Spacing.s12) {
                RoundedRectangle(cornerRadius: Radius.artwork).fill(FinifyColor.surface).frame(width: 52, height: 52)
                Text("Nothing playing")
                    .finifyFont(.caption)
                    .foregroundStyle(FinifyColor.faint)
            }
        }
    }
}

/// shuffle / 上一首 / 播放 / 下一首 / repeat。Standard 與 Overflow 共用。
struct PlaybackControls: View {
    var size: FinifyIcon.Size = .standard
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let player = app.player
        HStack(spacing: Spacing.s12) {
            FinifyIconButton(icon: .shuffle, label: player.isShuffled ? "Shuffle on" : "Shuffle off", size: .compact, isActive: player.isShuffled) {
                player.toggleShuffle()
            }
            FinifyIconButton(icon: .skipPrev, label: "Previous", size: size) { player.previous() }
            FinifyIconButton(icon: player.isPlaying ? .pause : .play, label: player.isPlaying ? "Pause" : "Play", size: size, prominent: true) {
                player.togglePlayPause()
            }
            FinifyIconButton(icon: .skipNext, label: "Next", size: size) { player.next() }
            FinifyIconButton(icon: player.repeatMode == .one ? .repeatOne : .repeat, label: repeatLabel, size: .compact, isActive: player.repeatMode != .off) {
                player.cycleRepeat()
            }
        }
        .disabled(player.currentTrack == nil)
    }

    private var repeatLabel: String {
        switch app.player.repeatMode {
        case .off: "Repeat off"
        case .all: "Repeat all"
        case .one: "Repeat one"
        }
    }
}

struct VolumeControl: View {
    @Environment(AppEnvironment.self) private var app
    @State private var lastVolume: Float = 0.8

    var body: some View {
        let player = app.player
        HStack(spacing: Spacing.s4) {
            FinifyIconButton(icon: player.volume == 0 ? .volumeOff : (player.volume < 0.5 ? .volumeLow : .volumeHigh), label: player.volume == 0 ? "Unmute" : "Mute", size: .compact) {
                if player.volume == 0 { player.volume = lastVolume } else { lastVolume = player.volume; player.volume = 0 }
            }
            ProgressBar(value: Double(player.volume), continuous: true) { player.volume = Float($0) }
                .frame(width: 88)
                .accessibilityLabel("Volume")
        }
    }
}

/// 右側滑出的播放佇列
struct QueuePanel: View {
    let onOpenAlbum: (String?) -> Void
    /// 放在 Now Playing 面板裡時不顯示自己的標題列與「正在播放」
    var embedded = false
    @Environment(AppEnvironment.self) private var app
    @State private var isTargeted = false
    /// 拖曳中的列（upcoming 內的位置）
    @State private var dragging: Int?

    var body: some View {
        let player = app.player
        VStack(alignment: .leading, spacing: 0) {
            if !embedded {
            HStack {
                Text("Queue").finifyFont(.heading).foregroundStyle(FinifyColor.ink)
                Spacer()
                if !player.queue.upcoming.isEmpty {
                    FinifyButton(title: "Clear", kind: .ghost) { player.clearUpcoming() }
                }
                FinifyIconButton(icon: .x, label: "Close queue") { app.isQueuePresented = false }
            }
            .padding(Spacing.s16)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    if !embedded, let current = player.currentTrack {
                        label("Now playing")
                        TrackRow(track: current, showsArtwork: true, onPlay: { player.togglePlayPause() }, onOpenAlbum: { onOpenAlbum(current.albumID) })
                    }
                    if !player.queue.upcoming.isEmpty {
                        label("Next").padding(.top, embedded ? 0 : Spacing.s16)
                        ForEach(Array(player.queue.upcomingEntries.enumerated()), id: \.element.id) { offset, entry in
                            let track = entry.track
                            TrackRow(track: track, showsArtwork: true, onPlay: { player.jump(toQueuePosition: player.queue.index + 1 + offset) })
                                .opacity(dragging == offset ? 0.4 : 1)
                                .onDrag {
                                    dragging = offset
                                    return NSItemProvider(object: String(offset) as NSString)
                                }
                                .onDrop(of: [.text, .url], delegate: QueueDropDelegate(target: offset, dragging: $dragging, player: player, app: app))
                                .accessibilityAction(named: "Move Up") { if offset > 0 { player.moveUpcoming(from: [offset], to: offset - 1) } }
                                .accessibilityAction(named: "Move Down") { player.moveUpcoming(from: [offset], to: offset + 2) }
                                .contextMenu {
                                    Button("Play") { player.jump(toQueuePosition: player.queue.index + 1 + offset) }
                                    Button("Remove from Queue") { player.removeUpcoming(at: offset) }
                                }
                        }
                    } else if player.currentTrack != nil {
                        Text("Nothing up next. Add songs with “Add to Queue”.")
                            .finifyFont(.caption)
                            .foregroundStyle(FinifyColor.faint)
                            .padding(.horizontal, Spacing.s12)
                            .padding(.top, Spacing.s16)
                    } else {
                        MessageState(title: "Your queue is empty", message: "Play an album or a song and it will show up here.", icon: .playlist)
                    }
                }
                .padding(.horizontal, Spacing.s8)
                .padding(.bottom, Spacing.s16)
            }
        }
        .background(embedded ? Color.clear : FinifyColor.elevated)
        .overlay(alignment: .leading) { if !embedded { FinifyColor.hairline.frame(width: 1) } }
        // 從專輯卡片拖進來：加到佇列結尾
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: Radius.ui, style: .continuous)
                    .strokeBorder(FinifyColor.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .padding(Spacing.s4)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { items, _ in
            dragging = nil
            let ids = items.compactMap(DragPayload.albumID(from:))
            guard !ids.isEmpty else { return false }
            Task {
                for id in ids {
                    if let tracks = try? await app.repository?.tracks(inAlbum: id) { app.player.addToQueue(tracks) }
                }
            }
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .finifyFont(.micro)
            .textCase(.uppercase)
            .foregroundStyle(FinifyColor.muted)
            .padding(.horizontal, Spacing.s12)
            .padding(.bottom, Spacing.s4)
    }
}

/// 拖曳排序：拖進另一列時即時移動，放開時結束
private struct QueueDropDelegate: DropDelegate {
    let target: Int
    @Binding var dragging: Int?
    let player: PlayerManager
    let app: AppEnvironment

    /// 專輯拖曳是 URL、佇列內排序是純文字；以型別判斷，殘留的 `dragging`（取消拖曳時不會清除）不會誤判
    private func isReorder(_ info: DropInfo) -> Bool { dragging != nil && !info.hasItemsConforming(to: [.url]) }

    func dropEntered(info: DropInfo) {
        guard isReorder(info), let from = dragging, from != target else { return }
        withAnimation(Motion.micro) {
            player.moveUpcoming(from: [from], to: target > from ? target + 1 : target)
        }
        dragging = target
    }

    /// 佇列內排序用 move；從專輯卡片拖進來的只允許 copy（回 move 會被系統拒絕）
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: isReorder(info) ? .move : .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard !isReorder(info) else {
            dragging = nil
            return true
        }
        dragging = nil
        // 從專輯卡片拖進來：加到佇列結尾
        for provider in info.itemProviders(for: [.url]) {
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                guard let url = object as? URL, let id = DragPayload.albumID(from: url) else { return }
                Task { @MainActor in
                    if let tracks = try? await app.repository?.tracks(inAlbum: id) { player.addToQueue(tracks) }
                }
            }
        }
        return true
    }
}
