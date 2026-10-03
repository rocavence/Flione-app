import AppKit

/// Infinity／Cover Flow 的「Magic」排序：用封面顏色、曲風、年代這類好玩的條件重新排列音樂庫。
/// 選了 Magic 會暫時取代一般排序；改回一般排序時自動關閉。
enum MagicSort: String, CaseIterable, Sendable {
    case shuffle = "Shuffle"
    case rainbow = "Rainbow"
    case lightToDark = "Light to Dark"
    case genre = "By Genre"
    case timeTravel = "Time Travel"

    var subtitle: String {
        switch self {
        case .shuffle: "A fresh random order every time"
        case .rainbow: "Covers flow through the color wheel"
        case .lightToDark: "From the brightest covers to the darkest"
        case .genre: "Grouped by genre"
        case .timeTravel: "From the oldest records to the newest"
        }
    }

    func apply(to albums: [Album]) -> [Album] {
        switch self {
        case .shuffle:
            return albums.shuffled()
        case .rainbow:
            // 有彩度的依色相排成彩虹；接近黑白灰的放在最後，由亮到暗
            let keyed = albums.map { ($0, Self.hsb(of: $0)) }
            let colorful = keyed.filter { ($0.1?.saturation ?? 0) >= 0.18 && ($0.1?.brightness ?? 0) >= 0.15 }
                .sorted { $0.1!.hue < $1.1!.hue }
            let neutral = keyed.filter { !(($0.1?.saturation ?? 0) >= 0.18 && ($0.1?.brightness ?? 0) >= 0.15) }
                .sorted { ($0.1?.brightness ?? -1) > ($1.1?.brightness ?? -1) }
            return (colorful + neutral).map(\.0)
        case .lightToDark:
            return albums.map { ($0, Self.luminance(of: $0)) }
                .sorted { ($0.1 ?? -1) > ($1.1 ?? -1) }
                .map(\.0)
        case .genre:
            // 依第一個曲風分群（沒有曲風的放最後），同一群內維持原本的藝人順序
            return albums.enumerated().sorted { a, b in
                switch (a.element.genres?.first, b.element.genres?.first) {
                case let (x?, y?) where x != y: return x.localizedStandardCompare(y) == .orderedAscending
                case (nil, _?): return false
                case (_?, nil): return true
                default: return a.offset < b.offset
                }
            }.map(\.element)
        case .timeTravel:
            return albums.enumerated().sorted { a, b in
                switch (a.element.year, b.element.year) {
                case let (x?, y?) where x != y: return x < y
                case (nil, _?): return false
                case (_?, nil): return true
                default: return a.offset < b.offset
                }
            }.map(\.element)
        }
    }

    /// 封面的平均色（取自 BlurHash，不需要下載圖片）
    private static func rgb(of album: Album) -> (r: Double, g: Double, b: Double)? {
        album.artwork?.blurHash.flatMap(BlurHash.averageColor)
    }

    private static func hsb(of album: Album) -> (hue: CGFloat, saturation: CGFloat, brightness: CGFloat)? {
        guard let c = rgb(of: album) else { return nil }
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0
        NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1).getHue(&h, saturation: &s, brightness: &v, alpha: nil)
        return (h, s, v)
    }

    private static func luminance(of album: Album) -> Double? {
        rgb(of: album).map { 0.2126 * $0.r + 0.7152 * $0.g + 0.0722 * $0.b }
    }
}
