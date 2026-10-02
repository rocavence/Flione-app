import AVFoundation
import Observation

/// 播放引擎（D01：AVQueuePlayer）。
/// AVQueuePlayer 只放「目前」與「下一首」兩個 item，讓下一首預先緩衝以達成無縫換曲；佇列邏輯在 `PlayQueue`。
/// 關閉 app 時的播放狀態，下次啟動時恢復（暫停在原位置）
struct PlaybackSnapshot: Codable {
    let owner: String
    let tracks: [Track]
    let index: Int
    let position: TimeInterval
    let repeatMode: String
}

struct PlayerNotice: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

@MainActor @Observable
final class PlayerManager {
    private(set) var queue = PlayQueue()
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    /// 播放失敗時給使用者看的訊息（顯示為 toast）
    private(set) var notice: PlayerNotice?
    /// 音量記在 UserDefaults（UI 偏好，不是敏感資料）
    var volume: Float = UserDefaults.standard.object(forKey: "FinifyVolume") as? Float ?? 0.8 {
        didSet {
            player.volume = volume
            UserDefaults.standard.set(volume, forKey: "FinifyVolume")
        }
    }

    var currentTrack: Track? { queue.current }
    var isShuffled: Bool { queue.isShuffled }
    var repeatMode: RepeatMode { queue.repeatMode }
    var progress: Double { duration > 0 ? currentTime / duration : 0 }

    @ObservationIgnored private let player = AVQueuePlayer()
    @ObservationIgnored private var repository: (any MusicRepository)?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    /// AVPlayerItem 對應的佇列項目（以 entry id 對應，佇列編輯後位置改變也不會錯）
    @ObservationIgnored private var itemEntries: [ObjectIdentifier: UUID] = [:]
    /// 目前正在播的 item；與 player.currentItem 不同時代表剛自動換曲
    @ObservationIgnored private var activeItem: ObjectIdentifier?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored var onTrackChange: ((Track?) -> Void)?

    init() {
        player.volume = volume
        player.actionAtItemEnd = .advance
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
        observations.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in
                self?.isPlaying = status == .playing
                self?.isBuffering = status == .waitingToPlayAtSpecifiedRate
            }
        })
        observations.append(player.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.currentItemChanged() }
        })
    }

    #if DEBUG || BENCHMARK
    /// 測試時靜音，但不改動使用者記住的音量
    func muteForTesting() { player.volume = 0 }
    #endif

    func attach(repository: any MusicRepository) {
        self.repository = repository
    }

    // MARK: - 播放狀態保存與恢復

    func snapshot(owner: String) -> PlaybackSnapshot? {
        guard !queue.isEmpty else { return nil }
        let mode = switch queue.repeatMode { case .off: "off"; case .all: "all"; case .one: "one" }
        return PlaybackSnapshot(owner: owner, tracks: queue.tracks, index: queue.index, position: currentTime, repeatMode: mode)
    }

    /// 恢復佇列並停在上次的位置，不自動播放
    func restore(_ snapshot: PlaybackSnapshot) {
        guard queue.isEmpty, !snapshot.tracks.isEmpty else { return }
        queue = PlayQueue(tracks: snapshot.tracks, startAt: snapshot.index)
        queue.repeatMode = switch snapshot.repeatMode { case "all": .all; case "one": .one; default: .off }
        rebuildPlayer(announce: false)
        if snapshot.position > 1 { seek(to: snapshot.position) }
    }

    // MARK: - 控制

    func play(_ tracks: [Track], startAt index: Int = 0, shuffled: Bool = false) {
        guard !tracks.isEmpty else { return }
        reportStopped()
        let mode = queue.repeatMode
        queue = PlayQueue(tracks: tracks, startAt: index, shuffled: shuffled)
        queue.repeatMode = mode
        consecutiveFailures = 0
        rebuildPlayer()
        player.play()
    }

    func togglePlayPause() {
        // 緩衝中（rate ≠ 0 但尚未出聲）也要能暫停
        if player.rate != 0 || isPlaying { player.pause(); return }
        guard currentTrack != nil else { return }
        // 佇列已播完時，從目前曲目重新開始
        if player.currentItem == nil { rebuildPlayer() }
        // 恢復的佇列第一次按播放時才回報
        if reportedTrack == nil { trackStarted() }
        player.play()
    }

    func pause() { player.pause() }

    func next() {
        guard queue.advance(automatic: false) != nil else { return }
        reportStopped()
        rebuildPlayer()
        player.play()
    }

    /// 播放超過 3 秒時回到開頭；否則上一首
    func previous() {
        if currentTime > 3 || queue.index == 0 && repeatMode != .all {
            seek(to: 0)
            return
        }
        reportStopped()
        queue.goBack()
        rebuildPlayer()
        player.play()
    }

    func jump(toQueuePosition position: Int) {
        reportStopped()
        queue.jump(to: position)
        rebuildPlayer()
        player.play()
    }

    func seek(to seconds: TimeInterval) {
        currentTime = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func toggleShuffle() {
        queue.setShuffle(!queue.isShuffled)
        refreshNextItem()
    }

    func cycleRepeat() {
        let all = RepeatMode.allCases
        queue.repeatMode = all[(all.firstIndex(of: queue.repeatMode)! + 1) % all.count]
        refreshNextItem()
    }

    func playNext(_ tracks: [Track]) {
        if queue.isEmpty { play(tracks); return }
        queue.insertNext(tracks)
        refreshNextItem()
    }

    func addToQueue(_ tracks: [Track]) {
        if queue.isEmpty { play(tracks); return }
        queue.append(tracks)
        refreshNextItem()
    }

    func removeUpcoming(at offset: Int) {
        queue.removeUpcoming(at: offset)
        refreshNextItem()
    }

    func moveUpcoming(from source: IndexSet, to destination: Int) {
        queue.moveUpcoming(from: source, to: destination)
        refreshNextItem()
    }

    func clearUpcoming() {
        queue.clearUpcoming()
        refreshNextItem()
    }

    // MARK: - AVQueuePlayer 管理

    private func makeItem(_ entry: QueueEntry) -> AVPlayerItem? {
        guard let url = repository?.streamURL(for: entry.track) else { return nil }
        // MP3 經 HTTP 時，需要精確時間才能正確 seek 與無縫換曲（S2）
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 30
        itemEntries[ObjectIdentifier(item)] = entry.id
        return item
    }

    /// 清空並以目前曲目＋下一首重建。`announce` 為 false 時（恢復上次狀態）不回報開始播放
    private func rebuildPlayer(announce: Bool = true) {
        player.removeAllItems()
        itemEntries.removeAll()
        currentTime = 0
        reportedPosition = 0
        duration = currentTrack?.duration ?? 0
        guard let entry = queue.currentEntry, let item = makeItem(entry) else { return }
        activeItem = ObjectIdentifier(item)
        player.insert(item, after: nil)
        appendNextItem()
        if announce { trackStarted() } else { observeFailure(of: item) }
    }

    private var nextEntry: QueueEntry? {
        queue.nextIndex(automatic: true).map { queue.entries[$0] }
    }

    private func appendNextItem() {
        guard let entry = nextEntry, let item = makeItem(entry) else { return }
        player.insert(item, after: player.items().last)
    }

    /// 佇列改變後，若下一首變了才替換預載的 item（保留已緩衝的內容，維持無縫換曲）
    private func refreshNextItem() {
        // 佇列已播完時不要載入任何東西，否則下一首會直接變成目前曲目
        guard player.currentItem != nil else { return }
        let preloaded = player.items().dropFirst()
        if preloaded.count == 1, let item = preloaded.first,
           itemEntries[ObjectIdentifier(item)] == nextEntry?.id {
            return
        }
        for item in preloaded {
            player.remove(item)
            itemEntries[ObjectIdentifier(item)] = nil
        }
        appendNextItem()
    }

    /// AVQueuePlayer 自動前進到下一個 item（無縫換曲）
    private func currentItemChanged() {
        guard let item = player.currentItem else {
            // 佇列播完：停在最後一首
            if activeItem != nil { reportStopped() }
            activeItem = nil
            currentTime = 0
            return
        }
        let id = ObjectIdentifier(item)
        guard id != activeItem, let entryID = itemEntries[id],
              let position = queue.entries.firstIndex(where: { $0.id == entryID }) else { return }
        activeItem = id
        let live = Set(player.items().map(ObjectIdentifier.init))
        itemEntries = itemEntries.filter { live.contains($0.key) }

        reportStopped()
        queue.jump(to: position)
        currentTime = 0
        reportedPosition = 0
        duration = currentTrack?.duration ?? 0
        appendNextItem()
        trackStarted()
    }

    /// 曲目無法播放時：提示使用者並跳到下一首，不讓播放停在原地
    private func observeFailure(of item: AVPlayerItem) {
        // .initial：預載的 item 可能在變成目前曲目前就已經失敗
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let failed = ObjectIdentifier(item)
            Task { @MainActor in
                guard let self, self.activeItem == failed else { return }
                self.trackFailed()
            }
        }
    }

    /// 連續失敗次數。整個佇列都失敗過一輪就停下來，避免 repeat 開啟時無限跳歌
    @ObservationIgnored private var consecutiveFailures = 0

    private func trackFailed() {
        guard let track = currentTrack else { return }
        consecutiveFailures += 1
        let canSkip = queue.nextIndex(automatic: false) != nil && consecutiveFailures < queue.entries.count
        notice = PlayerNotice(message: canSkip
            ? "Couldn't play “\(track.name)”. Skipping to the next song."
            : "Couldn't play “\(track.name)”. Check that your music server is reachable.")
        if canSkip { next() } else { player.pause() }
    }

    func dismissNotice() { notice = nil }

    private func tick(_ time: CMTime) {
        guard time.isValid, time.seconds.isFinite else { return }
        currentTime = time.seconds
        // 只記錄正在回報的那一首的位置，換曲瞬間不會被新曲目的時間覆蓋
        if let item = player.currentItem, ObjectIdentifier(item) == activeItem {
            reportedPosition = time.seconds
            if time.seconds > 1 { consecutiveFailures = 0 }
        }
        if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
            duration = itemDuration
        }
    }

    /// 登出或切換帳號時：停止播放、清空佇列與 Now Playing
    func stop() {
        reportStopped()
        player.removeAllItems()
        itemEntries.removeAll()
        activeItem = nil
        queue = PlayQueue()
        currentTime = 0
        duration = 0
        notice = nil
    }

    // MARK: - 播放回報（讓 Jellyfin 記錄最近播放）

    @ObservationIgnored private var reportedTrack: Track?
    @ObservationIgnored private var reportedPosition: TimeInterval = 0

    private func trackStarted() {
        guard let track = currentTrack else { return }
        reportedTrack = track
        onTrackChange?(track)
        if let item = player.currentItem { observeFailure(of: item) }
        Task { await repository?.reportPlaybackStarted(track) }
    }

    private func reportStopped() {
        guard let track = reportedTrack else { return }
        let position = reportedPosition
        reportedTrack = nil
        Task { await repository?.reportPlaybackStopped(track, position: position) }
    }
}
