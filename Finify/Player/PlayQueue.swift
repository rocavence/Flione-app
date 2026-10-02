import Foundation

/// 播放佇列的純邏輯（不碰 AVFoundation），方便測試。
struct PlayQueue: Sendable {
    /// 實際播放順序（shuffle 時為打亂後的順序）
    private(set) var tracks: [Track] = []
    /// shuffle 前的原始順序，關閉 shuffle 時用來還原
    private var original: [Track] = []
    private(set) var index = 0
    private(set) var isShuffled = false
    var repeatMode: RepeatMode = .off

    init() {}

    init(tracks: [Track], startAt: Int = 0, shuffled: Bool = false) {
        self.tracks = tracks
        self.original = tracks
        self.index = min(max(0, startAt), max(0, tracks.count - 1))
        if shuffled { setShuffle(true) }
    }

    var current: Track? { tracks.indices.contains(index) ? tracks[index] : nil }
    var upcoming: ArraySlice<Track> { tracks.indices.contains(index) ? tracks[(index + 1)...] : [] }
    var isEmpty: Bool { tracks.isEmpty }

    /// 目前曲目結束後要播的位置。`automatic` 為自然播完（repeat one 會重播同一首）。
    func nextIndex(automatic: Bool) -> Int? {
        guard !tracks.isEmpty else { return nil }
        if automatic, repeatMode == .one { return index }
        if index + 1 < tracks.count { return index + 1 }
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
        if index > 0 { index -= 1 } else if repeatMode == .all, !tracks.isEmpty { index = tracks.count - 1 }
        return current
    }

    mutating func jump(to position: Int) {
        guard tracks.indices.contains(position) else { return }
        index = position
    }

    /// 開啟時：目前曲目保持不動，之後的曲目打亂。關閉時：回到原始順序中目前曲目的位置。
    mutating func setShuffle(_ on: Bool) {
        guard on != isShuffled else { return }
        isShuffled = on
        guard let current else { return }
        if on {
            var rest = tracks
            rest.remove(at: index)
            tracks = [current] + rest.shuffled()
            index = 0
        } else {
            tracks = original
            index = original.firstIndex(of: current) ?? 0
        }
    }

    mutating func append(_ new: [Track]) {
        tracks += new
        original += new
    }

    mutating func insertNext(_ new: [Track]) {
        let at = tracks.isEmpty ? 0 : index + 1
        tracks.insert(contentsOf: new, at: at)
        if let current, let originalIndex = original.firstIndex(of: current) {
            original.insert(contentsOf: new, at: originalIndex + 1)
        } else {
            original += new
        }
    }

    /// 移除「接下來」清單中的第 offset 首（0 = 下一首）
    mutating func removeUpcoming(at offset: Int) {
        let position = index + 1 + offset
        guard tracks.indices.contains(position) else { return }
        let removed = tracks.remove(at: position)
        if let originalIndex = original.firstIndex(of: removed) { original.remove(at: originalIndex) }
    }

    mutating func moveUpcoming(from source: IndexSet, to destination: Int) {
        var upcoming = Array(self.upcoming)
        upcoming.move(fromOffsets: source, toOffset: destination)
        tracks = Array(tracks[...index]) + upcoming
        if !isShuffled { original = tracks }
    }

    mutating func clearUpcoming() {
        guard let current else { return }
        tracks = Array(tracks[...index])
        if !isShuffled { original = tracks } else { original = original.filter { tracks.contains($0) || $0 == current } }
    }
}
