import Foundation
import Network
import Observation

enum AppMode: String, Sendable {
    case standard, overflow
}

/// App 層的狀態與依賴：登入、repository、artwork、播放器、目前 mode。
@MainActor @Observable
final class AppEnvironment {
    private(set) var session: JellyfinSession?
    private(set) var repository: (any MusicRepository)?
    private(set) var images: ImagePipeline?
    let player = PlayerManager()
    let library = LibraryStore()

    /// nil = 尚未選擇（首次登入後顯示 mode picker）
    var mode: AppMode? {
        didSet {
            if rememberMode { UserDefaults.standard.set(mode?.rawValue, forKey: Self.modeKey) }
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
    var isQueuePresented = false

    @ObservationIgnored private let sessionStore: any SessionStore
    @ObservationIgnored private var nowPlaying: NowPlayingController?
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var wasOffline = false
    @ObservationIgnored private var expiryObserver: NSObjectProtocol?
    private static let modeKey = "FinifyMode"
    private static let rememberKey = "FinifyRememberMode"

    init(sessionStore: any SessionStore) {
        self.sessionStore = sessionStore
        rememberMode = UserDefaults.standard.object(forKey: Self.rememberKey) as? Bool ?? true
        mode = rememberMode ? UserDefaults.standard.string(forKey: Self.modeKey).flatMap(AppMode.init) : nil
        nowPlaying = NowPlayingController(player: player) { [weak self] in self?.images }
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
        player.pause()
        sessionStore.clear()
        session = nil
        repository = nil
        images = nil
        library.reset()
    }

    private func activate(_ session: JellyfinSession) {
        self.session = session
        UserDefaults.standard.set(session.serverURL.absoluteString, forKey: "FinifyLastServer")
        let repository = JellyfinRepository(session: session)
        self.repository = repository
        images = ImagePipeline { ref, size in repository.artworkURL(ref, maxPixelSize: size) }
        player.attach(repository: repository)
        library.attach(repository: repository, serverID: session.serverURL.absoluteString + session.userID)
    }
}
