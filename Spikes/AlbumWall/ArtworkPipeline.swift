import AppKit
import ImageIO
import os

struct Album: Identifiable, Sendable {
    let id: Int
    /// 對應到假封面檔案；1 萬張專輯共用 300 個檔案，但 cache key 用 album id，所以視為不同圖片
    var fileIndex: Int { id % 300 }
    /// 模擬 BlurHash / dominant color placeholder
    var placeholderHue: Double { Double(id % 37) / 37 }
}

enum Density: String, CaseIterable, Sendable {
    case small, medium, large

    var side: CGFloat {
        switch self {
        case .small: 120
        case .medium: 180
        case .large: 260
        }
    }

    /// 依 density 請求對應尺寸（LOD），2x 螢幕
    var pixelSize: Int { Int(side * 2) }
}

final class CGImageBox {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

/// 模擬 Flione 的 artwork pipeline：memory cache（有 byte 上限）→ disk（假封面檔）＋ 模擬網路延遲。
final class ArtworkPipeline: @unchecked Sendable {
    struct Stats: Sendable {
        var requested = 0
        var decoded = 0
        var cancelled = 0
        var cacheHits = 0
    }

    let cache = NSCache<NSString, CGImageBox>()
    let directory: URL
    let latency: ClosedRange<Double>
    private let stats = OSAllocatedUnfairLock(initialState: Stats())

    init(directory: URL, budgetMB: Int, latency: ClosedRange<Double>) {
        self.directory = directory
        self.latency = latency
        cache.totalCostLimit = budgetMB * 1024 * 1024
    }

    var snapshot: Stats { stats.withLock { $0 } }

    private func key(_ album: Album, _ px: Int) -> NSString { "\(album.id)@\(px)" as NSString }

    func cached(_ album: Album, px: Int) -> CGImage? {
        guard let box = cache.object(forKey: key(album, px)) else { return nil }
        stats.withLock { $0.cacheHits += 1 }
        return box.image
    }

    func load(_ album: Album, px: Int) async -> CGImage? {
        if let hit = cached(album, px: px) { return hit }
        stats.withLock { $0.requested += 1 }

        // 模擬 Jellyfin 回應時間
        try? await Task.sleep(for: .milliseconds(Int(Double.random(in: latency) * 1000)))
        if Task.isCancelled {
            stats.withLock { $0.cancelled += 1 }
            return nil
        }

        let url = directory.appendingPathComponent(String(format: "%03d.jpg", album.fileIndex))
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: px,
                  kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary)
        else { return nil }

        cache.setObject(CGImageBox(image), forKey: key(album, px), cost: image.bytesPerRow * image.height)
        stats.withLock { $0.decoded += 1 }
        return image
    }
}
