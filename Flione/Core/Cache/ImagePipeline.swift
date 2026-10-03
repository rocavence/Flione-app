import AppKit
import CryptoKit
import Foundation
import ImageIO
import os

final class CGImageBox: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

/// Artwork 載入：memory cache（有 byte 上限）→ disk cache → Jellyfin。
/// Jellyfin 依尺寸縮圖後回傳；本機再以 ImageIO downsample 解碼，不在 main thread 解碼原圖。
final class ImagePipeline: @unchecked Sendable {
    /// S3 建議值：捲動萬張專輯時記憶體穩定在可接受範圍
    static let memoryBudgetMB = 100
    static let diskBudgetMB = 500

    private let memory = NSCache<NSString, CGImageBox>()
    private let diskDirectory: URL
    private let urlProvider: @Sendable (ArtworkRef, Int) -> URL
    private let session: URLSession
    private let lock = NSLock()
    private var inFlight: [String: Task<CGImage?, Never>] = [:]

    init(urlProvider: @escaping @Sendable (ArtworkRef, Int) -> URL) {
        self.urlProvider = urlProvider
        memory.totalCostLimit = Self.memoryBudgetMB * 1024 * 1024
        diskDirectory = Self.diskDirectoryURL
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.httpMaximumConnectionsPerHost = 8
        session = URLSession(configuration: config)
        Task.detached(priority: .background) { [diskDirectory] in Self.trimDisk(diskDirectory) }
    }

    /// 尺寸分級，讓相近尺寸共用快取
    static func bucket(_ pixels: Int) -> Int {
        [96, 192, 320, 480, 720, 1080, 1600].first { $0 >= pixels } ?? 1600
    }

    private func key(_ ref: ArtworkRef, _ bucket: Int) -> String { "\(ref.itemID)-\(ref.tag)-\(bucket)" }

    func cached(_ ref: ArtworkRef, pixelSize: Int) -> CGImage? {
        memory.object(forKey: key(ref, Self.bucket(pixelSize)) as NSString)?.image
    }

    func image(_ ref: ArtworkRef, pixelSize: Int) async -> CGImage? {
        let bucket = Self.bucket(pixelSize)
        let key = key(ref, bucket)
        if let hit = memory.object(forKey: key as NSString) { return hit.image }

        let task: Task<CGImage?, Never> = lock.withLock {
            if let existing = inFlight[key] { return existing }
            let task = Task.detached(priority: .userInitiated) { [self] in
                let image = await self.load(ref, bucket: bucket, key: key)
                self.lock.withLock { self.inFlight[key] = nil }
                return image
            }
            inFlight[key] = task
            return task
        }
        return await task.value
    }

    private func load(_ ref: ArtworkRef, bucket: Int, key: String) async -> CGImage? {
        let file = diskDirectory.appendingPathComponent(Self.fileName(key))
        var data = try? Data(contentsOf: file)
        if data == nil {
            guard let (downloaded, response) = try? await session.data(from: urlProvider(ref, bucket)),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            try? downloaded.write(to: file, options: .atomic)
            data = downloaded
        }
        guard let data else { return nil }
        guard let image = Self.decode(data, maxPixelSize: bucket) else {
            // 磁碟上的檔案損毀：刪掉，下次重新下載
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        memory.setObject(CGImageBox(image), forKey: key as NSString, cost: image.bytesPerRow * image.height)
        return image
    }

    static func decode(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { return nil }
        return preparedForDisplay(thumbnail)
    }

    /// 主螢幕的色彩空間。外接螢幕常用自己的 ICC 描述檔（不是 sRGB），影像要轉成這個空間 Core Animation 才不用再轉
    /// 背景解碼讀取、main thread 在螢幕改變時寫入，以 lock 保護
    private static let displayColorSpace = OSAllocatedUnfairLock<CGColorSpace?>(initialState: CGColorSpace(name: CGColorSpace.sRGB))
    nonisolated(unsafe) private static var screenObserver: NSObjectProtocol?

    /// 在 main thread 呼叫：記下主螢幕色彩空間，螢幕改變時更新
    @MainActor
    static func trackDisplayColorSpace() {
        let update: @Sendable () -> Void = { displayColorSpace.withLock { $0 = NSScreen.main?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) } }
        update()
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            update()
        }
    }

    /// 在背景 thread 把影像重畫成螢幕原生格式（螢幕色彩空間、premultiplied BGRA）。
    /// 否則 Core Animation 會在 main thread 逐張做色彩轉換，捲動時掉 frame（Instruments 實測佔 main thread 16–23%）
    static func preparedForDisplay(_ image: CGImage) -> CGImage {
        guard let space = displayColorSpace.withLock({ $0 }) ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage() ?? image
    }

    private static func fileName(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined() + ".img"
    }

    static var diskDirectoryURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.finify.Finify/Artwork", isDirectory: true)
    }

    static func diskCacheSizeDescription() -> String {
        let files = (try? FileManager.default.contentsOfDirectory(at: diskDirectoryURL, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let bytes = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static func clearDiskCache() {
        try? FileManager.default.removeItem(at: diskDirectoryURL)
        try? FileManager.default.createDirectory(at: diskDirectoryURL, withIntermediateDirectories: true)
    }

    /// 超過 disk 上限時，刪除最久沒用的檔案
    private static func trimDisk(_ directory: URL) {
        let keys: [URLResourceKey] = [.contentAccessDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return }
        var entries = files.compactMap { url -> (URL, Date, Int)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, values.contentAccessDate ?? .distantPast, values.fileSize ?? 0)
        }
        var total = entries.reduce(0) { $0 + $1.2 }
        let budget = diskBudgetMB * 1024 * 1024
        guard total > budget else { return }
        entries.sort { $0.1 < $1.1 }
        for (url, _, size) in entries where total > budget {
            try? FileManager.default.removeItem(at: url)
            total -= size
        }
    }
}
