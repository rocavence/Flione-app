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
            remote?.volume = volume
            UserDefaults.standard.set(volume, forKey: "FinifyVolume")
        }
    }

    /// 點播放後、曲目還在向 server 取得時，用專輯資訊暫代目前曲目，畫面立刻進入播放狀態（D26）
    private(set) var pending: Track?
    @ObservationIgnored private var pendingTask: Task<Void, Never>?
    var currentTrack: Track? { pending ?? queue.current }
    var isShuffled: Bool { queue.isShuffled }
    /// Smart Shuffle：shuffle 之外，每隔幾首插入 Jellyfin Instant Mix 推薦的歌（見 D18）
    private(set) var isSmartShuffle = false
    /// 電台名稱（專輯、藝人或曲風）；nil 表示不是電台。電台快播完時自動補歌（D47）
    private(set) var radioName: String?
    @ObservationIgnored private var refillingRadio = false
    @ObservationIgnored private var refillingSuggestions = false
    private static let suggestEvery = 3
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
            // 佇列播完時 rate 仍是 1，狀態會停在 waiting（noItemToPlay），這不算播放中
            let waiting = status == .waitingToPlayAtSpecifiedRate && player.reasonForWaitingToPlay != .noItemToPlay
            Task { @MainActor in
                // YouTube Music、Chromecast 由外部引擎播放，AVQueuePlayer 沒有 item，它的狀態不算數
                guard let self, self.remote == nil else { return }
                // 按下播放就算播放中，緩衝不讓按鈕跳回「播放」；正在取曲目時維持使用者按下的狀態
                if self.pending == nil { self.isPlaying = status == .playing || waiting }
                self.isBuffering = waiting
                self.watchStall(waiting)
            }
        })
        observations.append(player.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.currentItemChanged() }
        })
    }

    #if DEBUG || BENCHMARK
    /// 測試時靜音，但不改動使用者記住的音量；也不回報播放，避免測試弄亂 Jellyfin 的播放紀錄
    func muteForTesting() {
        player.volume = 0
        reportsPlayback = false
    }
    @ObservationIgnored private var reportsPlayback = true
    /// 無縫播放量測用
    var debugQueuePlayer: AVQueuePlayer { player }
    #endif

    /// 給 AirPlay 選單（AVRoutePickerView）指定要轉送的播放器
    var routingPlayer: AVPlayer { player }

    func attach(repository: any MusicRepository) {
        self.repository = repository
    }

    // MARK: - 外部播放引擎：YouTube Music 網頁播放器、Chromecast（D43）
    // 佇列、上一首／下一首、自動換歌仍由 Flione 管；外部引擎一次只播一首。沒有外部引擎時用 AVQueuePlayer。

    @ObservationIgnored private var remote: (any RemotePlaybackEngine)?
    /// 外部引擎目前載入的佇列項目；nil 代表還沒載入（例如恢復的佇列尚未按播放）
    @ObservationIgnored private var remoteLoadedEntry: UUID?
    @ObservationIgnored private var remoteLoadedAt = Date.distantPast
    /// 正在投放（Chromecast）；YouTube Music 的網頁播放器不算
    private(set) var isCasting = false

    /// YouTube Music 的網頁播放器；切回 Jellyfin 時傳 nil
    func attach(webPlayer: YouTubeWebPlayer?) {
        attachRemote(webPlayer)
        isCasting = false
    }

    private func attachRemote(_ engine: (any RemotePlaybackEngine)?) {
        remote?.onUpdate = nil
        remote = engine
        engine?.volume = volume
        engine?.onUpdate = { [weak self] update in self?.remoteUpdated(update) }
    }

    /// 開始投放：Mac 停止出聲，從目前的位置交給投放裝置（一次只從一個裝置出聲）
    func startCasting(_ engine: any RemotePlaybackEngine) {
        guard remote == nil || isCasting else { return }
        let position = currentTime
        let wasPlaying = isPlaying
        if isCasting { remote?.stop() }
        player.pause()
        player.removeAllItems()
        itemEntries.removeAll()
        activeItem = nil
        attachRemote(engine)
        isCasting = true
        currentTime = position
        guard let entry = queue.currentEntry else { return }
        if wasPlaying || pending != nil {
            loadInRemote(entry, at: position)
            isPlaying = true
        } else {
            remoteLoadedEntry = nil
            castResumePosition = position
        }
    }

    /// 停止投放：從投放裝置停下的位置回到 Mac 播放
    func stopCasting(resumeLocally: Bool = true) {
        guard isCasting else { return }
        let position = currentTime
        let wasPlaying = isPlaying
        remote?.stop()
        attachRemote(nil)
        isCasting = false
        remoteLoadedEntry = nil
        rebuildPlayer(announce: false)
        if position > 1 { seek(to: position) }
        if resumeLocally && wasPlaying { start() } else { isPlaying = false }
    }

    /// 暫停時開始投放：按播放才載入，從這個位置開始
    @ObservationIgnored private var castResumePosition: TimeInterval = 0

    private func loadInRemote(_ entry: QueueEntry, at position: TimeInterval = 0) {
        remoteLoadedEntry = entry.id
        remoteLoadedAt = .now
        let artwork = entry.track.artwork.flatMap { repository?.artworkURL($0, maxPixelSize: 600) }
        remote?.load(entry.track, url: repository?.streamURL(for: entry.track), artwork: artwork, at: position)
    }

    private func remoteUpdated(_ update: RemotePlaybackUpdate) {
        guard let entry = queue.currentEntry, remoteLoadedEntry == entry.id else { return }
        if update.failed {
            remoteLoadedEntry = nil
            isPlaying = false
            notice = PlayerNotice(message: String(localized: "The cast device couldn't play “\(entry.track.name)”. In Settings → Music Source, set a server address it can reach."))
            return
        }
        // 剛載入的 2 秒內，舊頁面的訊息可能還在，不據此判斷換歌；播放狀態也先維持使用者按下的
        let settled = Date().timeIntervalSince(remoteLoadedAt) > 2
        if pending == nil, update.playing || settled { isPlaying = update.playing }
        currentTime = update.time
        reportedPosition = update.time
        if update.duration > 0 { duration = update.duration }
        if update.time > 1 { consecutiveFailures = 0 }
        let switchedAway = update.trackID.map { $0 != entry.track.id } ?? false
        // 佇列播完後 YouTube 會自己接著播別首（自動播放）：跟著它，不然音樂還在播、畫面卻停在上一首
        if settled, switchedAway, queue.nextIndex(automatic: true) == nil, let id = update.trackID {
            // 換歌的瞬間網頁還是舊歌的資訊：等新歌開始播、歌名換掉再接手
            guard update.playing, let title = update.title, !title.isEmpty, title != entry.track.name else { return }
            adoptRemoteTrack(id: id, update)
            return
        }
        if settled, update.ended || switchedAway { remoteTrackEnded() }
    }

    /// 把引擎自己換到的歌加到佇列最後並設為目前播放；網頁已經在播，不重新載入
    private func adoptRemoteTrack(id: String, _ update: RemotePlaybackUpdate) {
        reportStopped()
        let artwork = update.artworkURL.flatMap { $0.hasPrefix("http") ? ArtworkRef(itemID: $0, tag: "ytfixed", blurHash: nil) : nil }
        let track = Track(id: id, name: update.title ?? "", albumID: nil, albumName: "", artistName: update.artist ?? "", artistID: nil,
                          trackNumber: nil, discNumber: nil, duration: update.duration, container: nil, artwork: artwork)
        queue.append([track])
        guard queue.advance(automatic: true) != nil, let entry = queue.currentEntry else { return }
        remoteLoadedEntry = entry.id
        remoteLoadedAt = .now
        currentTime = update.time
        duration = update.duration
        trackStarted()
    }

    /// 一首播完（或 YouTube 自己換到別首）：換成佇列的下一首；佇列播完就停下
    private func remoteTrackEnded() {
        reportStopped()
        guard queue.advance(automatic: true) != nil else {
            remote?.pause()
            isPlaying = false
            remoteLoadedEntry = nil
            return
        }
        rebuildPlayer()
        start()
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
        guard snapshot.position > 1, let item = player.currentItem else { return }
        currentTime = snapshot.position
        // HTTP 串流在 item 準備好之前 seek 可能被忽略
        restoreObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard item.status == .readyToPlay else { return }
            Task { @MainActor in
                self?.seek(to: snapshot.position)
                self?.restoreObservation = nil
            }
        }
    }

    @ObservationIgnored private var restoreObservation: NSKeyValueObservation?

    // MARK: - 控制

    func play(_ tracks: [Track], startAt index: Int = 0, shuffled: Bool = false) {
        guard !tracks.isEmpty else { return }
        cancelPending()
        reportStopped()
        let mode = queue.repeatMode
        isSmartShuffle = false
        radioName = nil
        queue = PlayQueue(tracks: tracks, startAt: index, shuffled: shuffled)
        queue.repeatMode = mode
        consecutiveFailures = 0
        rebuildPlayer()
        start()
    }

    /// 播放專輯：不等 server 回傳曲目，先暫停目前的歌、把專輯顯示為正在播放；取不到曲目時才提示
    func play(album: Album, shuffled: Bool = false) {
        guard let repository else { return }
        cancelPending()
        pending = Track(id: Track.placeholderPrefix + album.id, name: album.name, albumID: album.id, albumName: album.name,
                        artistName: album.artistName, artistID: album.artistID, trackNumber: nil, discNumber: nil,
                        duration: 0, container: nil, artwork: album.artwork)
        if let remote { remote.pause() } else { player.pause() }
        isPlaying = true
        currentTime = 0
        duration = 0
        notice = nil
        pendingTask = Task {
            let tracks = try? await repository.tracks(inAlbum: album.id)
            guard !Task.isCancelled else { return }
            if let tracks, !tracks.isEmpty {
                play(tracks, shuffled: shuffled)
            } else {
                cancelPending()
                isPlaying = false
                notice = PlayerNotice(message: tracks == nil
                    ? String(localized: "Couldn't play “\(album.name)”. Check that your music server is reachable.")
                    : String(localized: "“\(album.name)” has no songs to play."))
            }
        }
    }

    /// 開始電台：以 Instant Mix 產生第一批歌，之後剩不到 5 首時用目前這首再補
    func startRadio(seedID: String, name: String) {
        guard let repository else { return }
        Task {
            let mix = (try? await repository.radio(seedID: seedID, limit: 50)) ?? []
            guard !mix.isEmpty else {
                notice = PlayerNotice(message: String(localized: "Couldn't start “\(name)” radio. Try again in a moment."))
                return
            }
            play(mix)
            radioName = name
        }
    }

    /// 心情電台（D50）：開始的歌來自心情（曲風或 YouTube 的心情歌單），之後跟一般電台一樣用目前的歌補
    func startMoodRadio(_ mood: Mood) async {
        guard let repository else { return }
        let name = String(localized: mood.title)
        let mix = (try? await repository.moodTracks(mood, limit: 40)) ?? []
        guard !mix.isEmpty else {
            notice = PlayerNotice(message: String(localized: "Nothing in your library fits “\(name)” yet."))
            return
        }
        play(mix)
        radioName = name
    }

    /// 停止電台：目前的佇列照常播完，不再自動補歌
    func stopRadio() { radioName = nil }

    private func refillRadio() async {
        guard radioName != nil, !refillingRadio, let track = currentTrack, let repository,
              queue.upcomingEntries.count < 5 else { return }
        refillingRadio = true
        defer { refillingRadio = false }
        guard let mix = try? await repository.radio(seedID: track.id, limit: 40), radioName != nil else { return }
        // 最近播過或已在佇列的不再加入（YouTube 的同一首歌可能是不同 id 的 MV 版，所以也比歌名＋藝人）
        let recent = queue.tracks.suffix(300)
        let seen = Set(recent.map(\.id)).union(recent.map(\.radioKey))
        let fresh = mix.filter { !seen.contains($0.id) && !seen.contains($0.radioKey) }
        guard !fresh.isEmpty else { return }
        queue.append(Array(fresh.prefix(25)))
        refreshNextItem()
    }

    private func cancelPending() {
        pendingTask?.cancel()
        pendingTask = nil
        pending = nil
    }

    /// 呼叫 player.play() 後 timeControlStatus 要等一下才更新，先讓按鈕顯示播放中
    private func start() {
        if let remote {
            // 剛載入新頁面時，舊頁面還在；這時送「繼續播放」會先播一下舊的歌。新頁面會自動播放
            if Date().timeIntervalSince(remoteLoadedAt) > 1 { remote.resume() }
        } else {
            player.play()
        }
        isPlaying = true
    }

    func togglePlayPause() {
        // 還在取曲目時按暫停：取消這次播放
        if pending != nil { cancelPending(); isPlaying = false; return }
        if remote != nil {
            if isPlaying { pause(); return }
            guard let entry = queue.currentEntry else { return }
            if remoteLoadedEntry != entry.id {
                loadInRemote(entry, at: castResumePosition)
                castResumePosition = 0
                trackStarted()
            } else {
                remote?.resume()
            }
            isPlaying = true
            return
        }
        // 緩衝中（rate ≠ 0 但尚未出聲）也要能暫停
        if player.rate != 0 || isPlaying { pause(); return }
        guard currentTrack != nil else { return }
        // 佇列已播完時，從目前曲目重新開始
        if player.currentItem == nil { rebuildPlayer() }
        // 恢復的佇列第一次按播放時才回報
        if reportedTrack == nil { trackStarted() }
        start()
    }

    func pause() {
        if pending != nil { cancelPending() }
        if let remote { remote.pause() } else { player.pause() }
        isPlaying = false
    }

    func next() {
        guard pending == nil, queue.advance(automatic: false) != nil else { return }
        reportStopped()
        rebuildPlayer()
        start()
    }

    /// 播放超過 3 秒時回到開頭；否則上一首
    func previous() {
        guard pending == nil else { return }
        if currentTime > 3 || queue.index == 0 && repeatMode != .all {
            seek(to: 0)
            return
        }
        reportStopped()
        queue.goBack()
        rebuildPlayer()
        start()
    }

    func jump(toQueuePosition position: Int) {
        cancelPending()
        reportStopped()
        queue.jump(to: position)
        rebuildPlayer()
        start()
    }

    func seek(to seconds: TimeInterval) {
        currentTime = seconds
        if let remote { remote.seek(to: seconds); return }
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// 依序切換：關 → shuffle → Smart Shuffle → 關
    func toggleShuffle() {
        if isSmartShuffle {
            isSmartShuffle = false
            queue.setShuffle(false)
        } else if queue.isShuffled {
            isSmartShuffle = true
            Task { await refillSuggestions() }
        } else {
            queue.setShuffle(true)
        }
        refreshNextItem()
    }

    /// 接下來的推薦少於 2 首時，用目前這首歌向 Jellyfin 要 Instant Mix 再補
    private func refillSuggestions() async {
        guard isSmartShuffle, !refillingSuggestions, let track = currentTrack, let repository,
              queue.upcomingEntries.filter(\.suggested).count < 2 else { return }
        refillingSuggestions = true
        defer { refillingSuggestions = false }
        guard let mix = try? await repository.instantMix(forTrack: track.id, limit: 30), isSmartShuffle else { return }
        queue.blendSuggestions(mix, every: Self.suggestEvery)
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
        if remote != nil {
            activeItem = nil
            currentTime = 0
            reportedPosition = 0
            duration = currentTrack?.duration ?? 0
            guard let entry = queue.currentEntry else { return }
            // 恢復的佇列不自動載入，按播放時才載入（見 togglePlayPause）
            if announce {
                loadInRemote(entry)
                trackStarted()
            } else {
                remoteLoadedEntry = nil
            }
            return
        }
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
        guard remote == nil else { return }
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
        // 恢復的佇列尚未按下播放（reportedTrack == nil）時不自動跳歌，避免啟動就開始播放
        let canSkip = reportedTrack != nil && queue.nextIndex(automatic: false) != nil && consecutiveFailures < queue.entries.count
        notice = PlayerNotice(message: canSkip
            ? String(localized: "Couldn't play “\(track.name)”. Skipping to the next song.")
            : String(localized: "Couldn't play “\(track.name)”. Check that your music server is reachable."))
        if canSkip { next() } else { pause() }
    }

    /// 已經按下播放卻一直在緩衝（server 很慢或連不到）時提示；不自動跳歌，連線恢復後會自己開始播
    @ObservationIgnored private var stallTask: Task<Void, Never>?
    private static let stallNoticeDelay: Duration = .seconds(8)

    private func watchStall(_ waiting: Bool) {
        guard waiting else { stallTask?.cancel(); stallTask = nil; return }
        guard stallTask == nil else { return }
        let item = activeItem
        stallTask = Task {
            try? await Task.sleep(for: Self.stallNoticeDelay)
            guard !Task.isCancelled else { return }
            stallTask = nil
            guard isBuffering, activeItem == item, let track = currentTrack else { return }
            notice = PlayerNotice(message: String(localized: "“\(track.name)” is taking a while to load. Check your connection to the music server."))
        }
    }

    func dismissNotice() { notice = nil }
    func post(notice message: String) { notice = PlayerNotice(message: message) }

    private func tick(_ time: CMTime) {
        guard remote == nil, time.isValid, time.seconds.isFinite else { return }
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
        cancelPending()
        reportStopped()
        remote?.stop()
        if isCasting { attachRemote(nil); isCasting = false }
        remoteLoadedEntry = nil
        player.removeAllItems()
        itemEntries.removeAll()
        activeItem = nil
        queue = PlayQueue()
        radioName = nil
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
        if isSmartShuffle { Task { await refillSuggestions() } }
        if radioName != nil { Task { await refillRadio() } }
        if let item = player.currentItem { observeFailure(of: item) }
        #if DEBUG || BENCHMARK
        guard reportsPlayback else { return }
        #endif
        Task { await repository?.reportPlaybackStarted(track) }
    }

    private func reportStopped() {
        guard let track = reportedTrack else { return }
        let position = reportedPosition
        reportedTrack = nil
        #if DEBUG || BENCHMARK
        guard reportsPlayback else { return }
        #endif
        Task { await repository?.reportPlaybackStopped(track, position: position) }
    }
}

extension Track {
    /// 電台去重用：歌名＋藝人（忽略大小寫）
    var radioKey: String { "\(name.lowercased())\u{1F}\(artistName.lowercased())" }

    static let placeholderPrefix = "pending:"
    /// 曲目還沒取回時暫代的項目（PlayerManager.pending），不能加愛心、查歌詞
    var isPlaceholder: Bool { id.hasPrefix(Self.placeholderPrefix) }
}
