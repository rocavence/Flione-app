import AppKit
import os
import UserNotifications

/// 換歌時發一則附封面的系統通知。只在 Flione 不在前景時發，避免和畫面重複。
/// 做法參考 Kaset（MIT）的 NotificationService。
@MainActor
final class TrackNotifier {
    private let images: () -> ImagePipeline?
    private var authorized: Bool?
    private var task: Task<Void, Never>?
    private static let identifier = "com.rocavence.Flione.now-playing"
    private let log = Logger(subsystem: "com.rocavence.Flione", category: "notifications")

    init(images: @escaping () -> ImagePipeline?) {
        self.images = images
        // 啟動時（app 在前景）就請求授權；在背景才請求會被系統直接拒絕
        if UserDefaults.standard.object(forKey: SettingsKey.trackNotifications) as? Bool ?? true {
            Task { await requestAuthorization() }
        }
    }

    func requestAuthorization() async {
        guard authorized == nil else { return }
        do {
            authorized = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
        } catch {
            log.error("authorization failed: \(String(describing: error), privacy: .public)")
            authorized = false
        }
    }

    func trackChanged(_ track: Track?) {
        task?.cancel()
        guard let track, UserDefaults.standard.object(forKey: SettingsKey.trackNotifications) as? Bool ?? true,
              !NSApp.isActive else { return }
        task = Task { await post(track) }
    }

    private func post(_ track: Track) async {
        let center = UNUserNotificationCenter.current()
        await requestAuthorization()
        guard authorized == true, !Task.isCancelled else {
            log.notice("notifications not authorized")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = track.name
        content.body = "\(track.artistName) — \(track.albumName)"
        if let attachment = await artworkAttachment(for: track) { content.attachments = [attachment] }
        guard !Task.isCancelled else { return }
        // 同一個 identifier：新通知取代上一首，通知中心不會堆一長串
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
        do {
            try await center.add(UNNotificationRequest(identifier: Self.identifier, content: content, trigger: nil))
        } catch {
            log.error("posting notification failed: \(error.localizedDescription)")
        }
    }

    private func artworkAttachment(for track: Track) async -> UNNotificationAttachment? {
        guard let ref = track.artwork, let images = images(),
              let image = await images.image(ref, pixelSize: 300) else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: "flione-notification-\(UUID().uuidString).png")
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
              (try? data.write(to: url)) != nil else { return nil }
        // 系統會把附件搬走，不必自己刪
        return try? UNNotificationAttachment(identifier: "artwork", url: url)
    }
}
