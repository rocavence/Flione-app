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
                    // 超過一小時（1:02:00）或放大字級時加寬，不換行
                    Text(player.currentTime.formattedDuration)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(minWidth: 44, alignment: .trailing)
                    ProgressBar(value: player.progress) { player.seek(to: $0 * player.duration) }
                        .accessibilityLabel("Playback position")
                    Text(player.duration.formattedDuration)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(minWidth: 44, alignment: .leading)
                }
                .flioneFont(.caption)
                .monospacedDigit()
                .foregroundStyle(FlioneColor.muted)
                .disabled(player.currentTrack == nil)
            }
            .frame(maxWidth: 520)
            Spacer(minLength: 0)
            HStack(spacing: Spacing.s8) {
                FlioneIconButton(icon: .playlist, label: "Queue", isActive: app.isQueuePresented) {
                    app.isQueuePresented.toggle()
                }
                .keyboardShortcut("u", modifiers: [.command])
                    .disabled(app.player.currentTrack == nil)
                FlioneIconButton(icon: .notes2, label: "Lyrics", isActive: app.isLyricsPresented) {
                    app.isLyricsPresented.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
                VolumeControl()
            }
            .frame(width: 280, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.s24)
        .frame(height: 80)
        .background(FlioneColor.panel)
        .overlay(alignment: .top) { FlioneColor.hairline.frame(height: 1) }
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
                            .flioneFont(.bodyEmphasis)
                            .foregroundStyle(FlioneColor.ink)
                            .lineLimit(1)
                            .onTapGesture { onOpenAlbum(track.albumID) }
                        Text(track.artistName)
                            .flioneFont(.caption)
                            .foregroundStyle(FlioneColor.muted)
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
                RoundedRectangle(cornerRadius: Radius.artwork).fill(FlioneColor.surface).frame(width: 52, height: 52)
                Text("Nothing playing")
                    .flioneFont(.caption)
                    .foregroundStyle(FlioneColor.faint)
            }
        }
    }
}

/// shuffle / 上一首 / 播放 / 下一首 / repeat。Standard 與 Overflow 共用。
struct PlaybackControls: View {
    var size: FlioneIcon.Size = .standard
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let player = app.player
        HStack(spacing: Spacing.s12) {
            FlioneIconButton(icon: .shuffle, label: shuffleLabel, size: .compact, isActive: player.isShuffled, activeColor: FlioneColor.orange) {
                Haptics.perform(.toggle)
                player.toggleShuffle()
            }
            // Smart Shuffle：在 shuffle 圖示右上角加一個小點
            .overlay(alignment: .topTrailing) {
                if player.isSmartShuffle {
                    Circle().fill(FlioneColor.orange).frame(width: 5, height: 5).offset(x: -4, y: 5).allowsHitTesting(false)
                }
            }
            .help(Text(shuffleLabel))
            // shuffle、repeat 與主要控制（上一首、播放／暫停、下一首）拉開距離
            .padding(.trailing, Spacing.s16)
            FlioneIconButton(icon: .skipPrev, label: "Previous", size: size) {
                Haptics.perform(.playback)
                player.previous()
            }
            FlioneIconButton(icon: player.isPlaying ? .pause : .play, label: player.isPlaying ? "Pause" : "Play", size: size, prominent: true) {
                Haptics.perform(.playback)
                player.togglePlayPause()
            }
            FlioneIconButton(icon: .skipNext, label: "Next", size: size) {
                Haptics.perform(.playback)
                player.next()
            }
            FlioneIconButton(icon: player.repeatMode == .one ? .repeatOne : .repeat, label: repeatLabel, size: .compact, isActive: player.repeatMode != .off, activeColor: FlioneColor.orange) {
                Haptics.perform(.toggle)
                player.cycleRepeat()
            }
            .padding(.leading, Spacing.s16)
        }
        .disabled(player.currentTrack == nil)
    }

    private var shuffleLabel: LocalizedStringResource {
        let player = app.player
        return player.isSmartShuffle ? "Smart Shuffle on (adds similar songs)" : player.isShuffled ? "Shuffle on" : "Shuffle off"
    }

    private var repeatLabel: LocalizedStringResource {
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
            FlioneIconButton(icon: player.volume == 0 ? .volumeOff : (player.volume < 0.5 ? .volumeLow : .volumeHigh), label: player.volume == 0 ? "Unmute" : "Mute", size: .compact) {
                if player.volume == 0 { player.volume = lastVolume } else { lastVolume = player.volume; player.volume = 0 }
            }
            ProgressBar(value: Double(player.volume), continuous: true, isPlayback: false) { player.volume = Float($0) }
                .frame(width: 88)
                .accessibilityLabel("Volume")
        }
    }
}

/// 播放佇列的內容（正在播放＋接下來）；外框、標題與分頁由 PlayerSidePanel 提供
struct QueuePanel: View {
    let onOpenAlbum: (String?) -> Void
    @Environment(AppEnvironment.self) private var app
    @State private var isTargeted = false
    /// 拖曳中的列（upcoming 內的位置）
    @State private var dragging: Int?

    var body: some View {
        let player = app.player
        VStack(alignment: .leading, spacing: 0) {

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    if let current = player.currentTrack {
                        label("Now playing")
                        TrackRow(track: current, showsArtwork: true, showsPlayHistory: false, onPlay: { player.togglePlayPause() }, onOpenAlbum: { onOpenAlbum(current.albumID) })
                    }
                    if !player.queue.upcoming.isEmpty {
                        label("Next up").padding(.top, Spacing.s16)
                        ForEach(Array(player.queue.upcomingEntries.enumerated()), id: \.element.id) { offset, entry in
                            let track = entry.track
                            TrackRow(track: track, showsArtwork: true, suggested: entry.suggested, showsPlayHistory: false,
                                     onPlay: { player.jump(toQueuePosition: player.queue.index + 1 + offset) })
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
                            .flioneFont(.caption)
                            .foregroundStyle(FlioneColor.faint)
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
        // 從專輯卡片拖進來：加到佇列結尾
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: Radius.ui, style: .continuous)
                    .strokeBorder(FlioneColor.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
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

    private func label(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .flioneFont(.micro)
            .textCase(.uppercase)
            .foregroundStyle(FlioneColor.muted)
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
