import AppKit
import Network
import Observation

enum AppMode: String, Sendable {
    case standard, overflow
}

/// 使用者看到的三種模式。Infinity 與 Cover Flow 共用 Overflow 的畫面（深色、封面為主），只是版面不同。
enum ViewMode: CaseIterable, Sendable {
    case standard, infinity, coverFlow

    var title: String {
        switch self {
        case .standard: "Standard"
        case .infinity: "Infinity"
        case .coverFlow: "Cover Flow"
        }
    }

    var icon: Reicon {
        switch self {
        case .standard: .menu
        case .infinity: .infinite
        case .coverFlow: .carouselH
        }
    }

    var shortcut: Character {
        switch self {
        case .standard: "1"
        case .infinity: "2"
        case .coverFlow: "3"
        }
    }
}

/// App 層的狀態與依賴：登入、repository、artwork、播放器、目前 mode。
@MainActor @Observable
final class AppEnvironment {
    private(set) var session: JellyfinSession?
    private(set) var repository: (any MusicRepository)?
    private(set) var images: ImagePipeline?
    let player = PlayerManager()
    let library = LibraryStore()
    let favorites = FavoritesStore()
    let playlists = PlaylistStore()

    /// nil = 尚未選擇（首次登入後顯示 mode picker）
    var mode: AppMode? {
        didSet {
            // 佇列與歌詞在兩個 mode 的呈現方式不同（Standard 是側面板、Overflow 是浮層），切換時收起
            if oldValue != mode, oldValue != nil {
                isQueuePresented = false
                isLyricsPresented = false
            }
            if rememberMode { UserDefaults.standard.set(mode?.rawValue, forKey: Self.modeKey) }
        }
    }
    /// Overflow 畫面的版面：Infinity（封面牆）或 Cover Flow
    var overflowLayout: OverflowLayout = OverflowLayout(rawValue: UserDefaults.standard.string(forKey: "FinifyOverflowLayout") ?? "") ?? .wall {
        didSet { UserDefaults.standard.set(overflowLayout.rawValue, forKey: "FinifyOverflowLayout") }
    }

    var viewMode: ViewMode {
        get {
            guard mode == .overflow else { return .standard }
            return overflowLayout == .flow ? .coverFlow : .infinity
        }
        set {
            switch newValue {
            case .standard: mode = .standard
            case .infinity: overflowLayout = .wall; mode = .overflow
            case .coverFlow: overflowLayout = .flow; mode = .overflow
            }
        }
    }

    var rememberMode: Bool {
        didSet {
            UserDefaults.standard.set(rememberMode, forKey: Self.rememberKey)
            if !rememberMode { UserDefaults.standard.removeObject(forKey: Self.modeKey) }
        }
    }
    /// 回到登入畫面的原因（例如登入過期），顯示在 ConnectView
    var signOutReason: String?
    /// 網路恢復時遞增；失敗中的畫面據此重新載入
    private(set) var reconnectCount = 0
    var isSearchPresented = false
    /// 要建立新 playlist 時的曲目（非 nil 時顯示命名對話框）
    var newPlaylistTracks: [Track]?
    /// `finify://album/<id>` 要打開的專輯；由目前的 mode 打開後清掉
    var requestedAlbumID: String?
    /// 從 Standard 進入 Fullscreen 時記住原本的 mode，離開時回去
    var fullscreenReturnMode: AppMode?

    /// 從任何 mode 進入 Overflow 的 Fullscreen
    func enterFullscreenPlayer() {
        guard player.currentTrack != nil else { return }
        if mode != .overflow {
            fullscreenReturnMode = mode
            mode = .overflow
        }
        isFullscreenRequested = true
    }

    var isFullscreenRequested = false
    /// Overflow 的 Fullscreen 播放器是否開著
    var isImmersive = false
    var isQueuePresented = false {
        didSet { if isQueuePresented { isLyricsPresented = false } }
    }
    var isLyricsPresented = false {
        didSet { if isLyricsPresented { isQueuePresented = false } }
    }

    @ObservationIgnored private let sessionStore: any SessionStore
    @ObservationIgnored private var nowPlaying: NowPlayingController?
    @ObservationIgnored private var notifier: TrackNotifier?
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var wasOffline = false
    @ObservationIgnored private var expiryObserver: NSObjectProtocol?
    @ObservationIgnored private var terminateObserver: NSObjectProtocol?
    @ObservationIgnored private var lastSavedPlayback: Data?
    private static let modeKey = "FinifyMode"
    private static let rememberKey = "FinifyRememberMode"

    init(sessionStore: any SessionStore) {
        self.sessionStore = sessionStore
        rememberMode = UserDefaults.standard.object(forKey: Self.rememberKey) as? Bool ?? true
        mode = rememberMode ? UserDefaults.standard.string(forKey: Self.modeKey).flatMap(AppMode.init) : nil
        ImagePipeline.trackDisplayColorSpace()
        nowPlaying = NowPlayingController(player: player) { [weak self] in self?.images }
        let notifier = TrackNotifier { [weak self] in self?.images }
        self.notifier = notifier
        player.onTrackChange = { notifier.trackChanged($0) }
        if let session = sessionStore.load() { activate(session) }
        expiryObserver = NotificationCenter.default.addObserver(forName: .finifySessionExpired, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.session != nil else { return }
                self.signOut(reason: "Your session with the music server ended. Sign in again to keep listening.")
            }
        }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.networkChanged(online: path.status == .satisfied) }
        }
        pathMonitor.start(queue: .global(qos: .utility))
        terminateObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.savePlayback() }
        }
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                self?.savePlayback()
            }
        }
    }

    private func networkChanged(online: Bool) {
        defer { wasOffline = !online }
        guard online, wasOffline else { return }
        reconnectCount += 1
        if library.state == .failed { Task { await library.refresh() } }
    }

    /// 上次連線的 server 位址（不含帳密），用來預填登入畫面
    static var lastServerAddress: String? { UserDefaults.standard.string(forKey: "FinifyLastServer") }

    static func bootstrap() -> AppEnvironment {
        #if DEBUG || BENCHMARK
        if let path = UserDefaults.standard.string(forKey: "FinifySecrets") {
            let env = AppEnvironment(sessionStore: DevelopmentSessionStore(directory: URL(fileURLWithPath: path)))
            if let mode = UserDefaults.standard.string(forKey: "FinifyStartMode").flatMap(AppMode.init) { env.mode = mode }
            return env
        }
        // 當 test host 時不碰 Keychain：重新簽章後系統會跳授權框，test runner 會一直卡住
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return AppEnvironment(sessionStore: DevelopmentSessionStore(directory: FileManager.default.temporaryDirectory.appending(path: "FinifyTestHost")))
        }
        #endif
        return AppEnvironment(sessionStore: KeychainSessionStore())
    }

    func signIn(_ session: JellyfinSession) throws {
        try sessionStore.save(session)
        signOutReason = nil
        activate(session)
    }

    func signOut(reason: String? = nil) {
        signOutReason = reason
        player.stop()
        try? FileManager.default.removeItem(at: playbackFile)
        sessionStore.clear()
        session = nil
        repository = nil
        images = nil
        library.reset()
        favorites.reset()
        playlists.reset()
    }

    // MARK: - 播放狀態保存

    private var playbackFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.finify.Finify/playback.json")
    }

    private var sessionOwner: String? { session.map { $0.serverURL.absoluteString + "|" + $0.userID } }

    /// 每 10 秒與關閉 app 時保存；只恢復同一個 server 與使用者的狀態
    func savePlayback() {
        guard let owner = sessionOwner else { return }
        guard let snapshot = player.snapshot(owner: owner) else {
            try? FileManager.default.removeItem(at: playbackFile)
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot), data != lastSavedPlayback else { return }
        try? data.write(to: playbackFile, options: .atomic)
        lastSavedPlayback = data
    }

    private func restorePlayback() {
        guard let owner = sessionOwner, let data = try? Data(contentsOf: playbackFile),
              let snapshot = try? JSONDecoder().decode(PlaybackSnapshot.self, from: data), snapshot.owner == owner else { return }
        player.restore(snapshot)
    }

    private func activate(_ session: JellyfinSession) {
        self.session = session
        UserDefaults.standard.set(session.serverURL.absoluteString, forKey: "FinifyLastServer")
        let repository = JellyfinRepository(session: session)
        self.repository = repository
        images = ImagePipeline { ref, size in repository.artworkURL(ref, maxPixelSize: size) }
        player.attach(repository: repository)
        library.attach(repository: repository, serverID: session.serverURL.absoluteString + session.userID)
        favorites.attach(repository: repository)
        playlists.attach(repository: repository)
        restorePlayback()
    }
}
