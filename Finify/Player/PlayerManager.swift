import AVFoundation
import Observation

/// 播放引擎（D01：AVQueuePlayer）。
/// AVQueuePlayer 只放「目前」與「下一首」兩個 item，讓下一首預先緩衝以達成無縫換曲；佇列邏輯在 `PlayQueue`。
@MainActor @Observable
final class PlayerManager {
    private(set) var queue = PlayQueue()
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    /// 播放失敗時給使用者看的訊息
    private(set) var errorMessage: String?
    var volume: Float = 0.8 {
        didSet { player.volume = volume }
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
    /// AVPlayerItem 對應的 queue 位置
    @ObservationIgnored private var itemPositions: [ObjectIdentifier: Int] = [:]
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

    func attach(repository: any MusicRepository) {
        self.repository = repository
    }

    // MARK: - 控制

    func play(_ tracks: [Track], startAt index: Int = 0, shuffled: Bool = false) {
        guard !tracks.isEmpty else { return }
        reportStopped()
        queue = PlayQueue(tracks: tracks, startAt: index, shuffled: shuffled)
        queue.repeatMode = repeatMode
        rebuildPlayer()
        player.play()
    }

    func togglePlayPause() {
        if isPlaying { player.pause(); return }
        guard currentTrack != nil else { return }
        // 佇列已播完時，從目前曲目重新開始
        if player.currentItem == nil { rebuildPlayer() }
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

    private func makeItem(_ track: Track, position: Int) -> AVPlayerItem? {
        guard let url = repository?.streamURL(for: track) else { return nil }
        // MP3 經 HTTP 時，需要精確時間才能正確 seek 與無縫換曲（S2）
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 30
        itemPositions[ObjectIdentifier(item)] = position
        return item
    }

    /// 清空並以目前曲目＋下一首重建
    private func rebuildPlayer() {
        player.removeAllItems()
        itemPositions.removeAll()
        errorMessage = nil
        currentTime = 0
        duration = currentTrack?.duration ?? 0
        guard let track = currentTrack, let item = makeItem(track, position: queue.index) else { return }
        activeItem = ObjectIdentifier(item)
        player.insert(item, after: nil)
        appendNextItem()
        trackStarted()
    }

    private func appendNextItem() {
        guard let nextIndex = queue.nextIndex(automatic: true),
              let item = makeItem(queue.tracks[nextIndex], position: nextIndex) else { return }
        player.insert(item, after: player.items().last)
    }

    /// 佇列改變後，替換已預載的下一首
    private func refreshNextItem() {
        for item in player.items().dropFirst() {
            player.remove(item)
            itemPositions[ObjectIdentifier(item)] = nil
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
        guard id != activeItem, let position = itemPositions[id] else { return }
        activeItem = id
        let live = Set(player.items().map(ObjectIdentifier.init))
        itemPositions = itemPositions.filter { live.contains($0.key) }

        reportStopped()
        queue.jump(to: position)
        currentTime = 0
        duration = currentTrack?.duration ?? 0
        appendNextItem()
        trackStarted()
    }

    private func observeFailure(of item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in self?.errorMessage = "This track can't be played right now." }
        }
    }

    private func tick(_ time: CMTime) {
        guard time.isValid, time.seconds.isFinite else { return }
        currentTime = time.seconds
        if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
            duration = itemDuration
        }
    }

    // MARK: - 播放回報（讓 Jellyfin 記錄最近播放）

    @ObservationIgnored private var reportedTrack: Track?

    private func trackStarted() {
        guard let track = currentTrack else { return }
        reportedTrack = track
        onTrackChange?(track)
        if let item = player.currentItem { observeFailure(of: item) }
        Task { await repository?.reportPlaybackStarted(track) }
    }

    private func reportStopped() {
        guard let track = reportedTrack else { return }
        let position = currentTime
        reportedTrack = nil
        Task { await repository?.reportPlaybackStopped(track, position: position) }
    }
}
