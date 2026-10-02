import Foundation

/// 佇列中的一個位置。同一首歌可以出現多次（例如同一張專輯加入兩次），以 id 區分。
struct QueueEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let track: Track

    init(_ track: Track) {
        id = UUID()
        self.track = track
    }
}

/// 播放佇列的純邏輯（不碰 AVFoundation），方便測試。
struct PlayQueue: Sendable {
    /// 實際播放順序（shuffle 時為打亂後的順序）
    private(set) var entries: [QueueEntry] = []
    /// shuffle 前的原始順序，關閉 shuffle 時用來還原
    private var original: [QueueEntry] = []
    private(set) var index = 0
    private(set) var isShuffled = false
    var repeatMode: RepeatMode = .off

    init() {}

    init(tracks: [Track], startAt: Int = 0, shuffled: Bool = false) {
        entries = tracks.map(QueueEntry.init)
        original = entries
        index = min(max(0, startAt), max(0, entries.count - 1))
        if shuffled { setShuffle(true) }
    }

    var tracks: [Track] { entries.map(\.track) }
    var current: Track? { currentEntry?.track }
    var currentEntry: QueueEntry? { entries.indices.contains(index) ? entries[index] : nil }
    var upcomingEntries: ArraySlice<QueueEntry> { entries.indices.contains(index) ? entries[(index + 1)...] : [] }
    var upcoming: [Track] { upcomingEntries.map(\.track) }
    var isEmpty: Bool { entries.isEmpty }

    /// 目前曲目結束後要播的位置。`automatic` 為自然播完（repeat one 會重播同一首）。
    func nextIndex(automatic: Bool) -> Int? {
        guard !entries.isEmpty else { return nil }
        if automatic, repeatMode == .one { return index }
        if index + 1 < entries.count { return index + 1 }
        return repeatMode == .off ? nil : 0
    }

    /// 前進到下一首；沒有下一首時回傳 nil 且位置不變
    @discardableResult
    mutating func advance(automatic: Bool) -> Track? {
        guard let next = nextIndex(automatic: automatic) else { return nil }
        index = next
        return current
    }

    @discardableResult
    mutating func goBack() -> Track? {
        if index > 0 { index -= 1 } else if repeatMode == .all, !entries.isEmpty { index = entries.count - 1 }
        return current
    }

    mutating func jump(to position: Int) {
        guard entries.indices.contains(position) else { return }
        index = position
    }

    /// 開啟時：目前曲目保持不動，之後的曲目打亂。關閉時：回到原始順序中目前曲目的位置。
    mutating func setShuffle(_ on: Bool) {
        guard on != isShuffled else { return }
        isShuffled = on
        guard let current = currentEntry else { return }
        if on {
            var rest = entries
            rest.remove(at: index)
            entries = [current] + rest.shuffled()
            index = 0
        } else {
            entries = original
            index = original.firstIndex(of: current) ?? 0
        }
    }

    mutating func append(_ tracks: [Track]) {
        let new = tracks.map(QueueEntry.init)
        entries += new
        original += new
    }

    mutating func insertNext(_ tracks: [Track]) {
        let new = tracks.map(QueueEntry.init)
        let at = entries.isEmpty ? 0 : index + 1
        entries.insert(contentsOf: new, at: at)
        if let current = currentEntry, let originalIndex = original.firstIndex(of: current) {
            original.insert(contentsOf: new, at: originalIndex + 1)
        } else {
            original += new
        }
    }

    /// 移除「接下來」清單中的第 offset 首（0 = 下一首）
    mutating func removeUpcoming(at offset: Int) {
        let position = index + 1 + offset
        guard entries.indices.contains(position) else { return }
        let removed = entries.remove(at: position)
        original.removeAll { $0 == removed }
    }

    /// 在「接下來」清單內移動；destination 超出範圍時夾到最後
    mutating func moveUpcoming(from source: IndexSet, to destination: Int) {
        var upcoming = Array(upcomingEntries)
        guard source.allSatisfy(upcoming.indices.contains) else { return }
        upcoming.move(fromOffsets: source, toOffset: min(max(0, destination), upcoming.count))
        entries = Array(entries[...index]) + upcoming
        if !isShuffled { original = entries }
    }

    mutating func clearUpcoming() {
        guard let current = currentEntry else { return }
        let removed = Set(upcomingEntries)
        entries = Array(entries[...index])
        original = isShuffled ? original.filter { !removed.contains($0) || $0 == current } : entries
    }
}
