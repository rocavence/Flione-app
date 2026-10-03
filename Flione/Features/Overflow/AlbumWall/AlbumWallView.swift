import AppKit
import SwiftUI

enum WallDensity: Int, CaseIterable, Sendable {
    case tiny, small, medium, large, huge

    /// 封面牆的列數：以列數定義大小，封面永遠剛好填滿上下，任何視窗高度都整齊
    var rows: Int {
        switch self {
        case .tiny: 8
        case .small: 6
        case .medium: 5
        case .large: 4
        case .huge: 3
        }
    }

    /// 封面牆上方留給頂部列的空間；下方由播放列高度決定（AlbumWallView.bottomInset）
    static let topInset: CGFloat = 56

    /// 依可用高度挑最好看的大小：封面邊長最接近 200pt 的列數
    static func auto(forHeight height: CGFloat, bottomInset: CGFloat) -> WallDensity {
        let available = max(200, height - topInset - bottomInset)
        return allCases.min { abs(available / CGFloat($0.rows) - 200) < abs(available / CGFloat($1.rows) - 200) }!
    }

    /// pinch 結束時吸附到最接近的列數
    static func nearest(rows: CGFloat) -> WallDensity {
        allCases.min { abs(CGFloat($0.rows) - rows) < abs(CGFloat($1.rows) - rows) }!
    }

    /// 這個密度在指定可用高度下的封面邊長
    func side(forHeight height: CGFloat, bottomInset: CGFloat) -> CGFloat {
        let available = max(100, height - Self.topInset - bottomInset)
        return available / CGFloat(rows)
    }

    /// 只在 pinch 的上下限用
    var side: CGFloat {
        switch self {
        case .tiny: 64
        case .small: 96
        case .medium: 148
        case .large: 220
        case .huge: 320
        }
    }

    var label: String {
        switch self {
        case .tiny: "Tiny"
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .huge: "Huge"
        }
    }

}

/// Album Wall（D02：NSCollectionView）。只建立看得到的 cell 並重用；artwork 由 ImagePipeline 載入（有記憶體上限）。
struct AlbumWallView: NSViewRepresentable {
    let albums: [Album]
    @Binding var density: WallDensity
    let playingAlbumID: String?
    let images: ImagePipeline?
    let onOpen: (Album) -> Void
    let onPlay: (Album) -> Void
    let onQueue: (Album, _ next: Bool) -> Void
    /// 額外的右鍵選單項目（喜愛、加入 playlist）
    var extraMenu: ((Album) -> [NSMenuItem])?
    /// 捲動到正在播放的專輯；值改變時觸發
    var scrollToPlayingToken = 0
    /// 上方有專輯面板或搜尋時為 false，Return 不播放牆上選取的專輯
    var acceptsKeyboard = true
    /// 輸入文字跳轉時優先比對專輯名（依標題排序時）或藝人名
    var typeToSelectByTitle = false
    /// 下方留白：與浮動播放列之間的距離＝播放列到視窗底的距離
    var bottomInset: CGFloat = 100

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        // 左右捲動：依可用高度決定列數，封面剛好填滿頂部列與底部播放列之間
        let layout = WallRowsLayout()
        let collection = WallCollectionView()
        collection.collectionViewLayout = layout
        collection.dataSource = context.coordinator
        collection.delegate = context.coordinator
        collection.isSelectable = true
        collection.backgroundColors = [.clear]
        collection.register(WallItem.self, forItemWithIdentifier: WallItem.identifier)
        collection.coordinator = context.coordinator
        collection.setAccessibilityLabel("Album wall")

        let scroll = WallScrollView()
        scroll.documentView = collection
        scroll.drawsBackground = false
        // 以拖曳、滾輪捲動，不顯示捲軸（捲軸會蓋在底部播放列上）
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.onUserScroll = { [weak coordinator = context.coordinator] in coordinator?.motion.noteActivity() }

        let pinch = NSMagnificationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        collection.addGestureRecognizer(pinch)

        context.coordinator.collection = collection
        context.coordinator.applyDensity(density, animated: false)
        context.coordinator.motion.attach(to: collection)
        return scroll
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.motion.detach()
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let albumsChanged = coordinator.parent.albums.map(\.id) != albums.map(\.id)
        // binding 讀的是即時值，不能拿舊的 parent 比；改與目前實際尺寸比較
        let densityChanged = coordinator.currentRows != density.rows || coordinator.parent.bottomInset != bottomInset
        let playingChanged = coordinator.parent.playingAlbumID != playingAlbumID
        let scrollRequested = coordinator.parent.scrollToPlayingToken != scrollToPlayingToken
        coordinator.parent = self
        if albumsChanged {
            // 排序或內容改變後，同一個位置已是另一張專輯
            coordinator.collection?.deselectAll(nil)
            coordinator.collection?.reloadData()
        }
        if densityChanged && !coordinator.isPinching { coordinator.applyDensity(density, animated: true) }
        if playingChanged { coordinator.refreshPlaying() }
        if scrollRequested { coordinator.scrollToPlaying() }
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var parent: AlbumWallView
        weak var collection: NSCollectionView?
        /// 拖曳慣性與閒置時的緩慢漂移
        let motion = WallMotion()
        var isPinching = false
        private var pinchStartSide: CGFloat = 148
        private(set) var currentSide: CGFloat = 148
        /// 目前套用的列數；pinch 進行中為 nil
        private(set) var currentRows: Int?

        init(parent: AlbumWallView) { self.parent = parent }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.albums.count
        }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: WallItem.identifier, for: indexPath) as! WallItem
            let album = parent.albums[indexPath.item]
            let side = (collectionView.collectionViewLayout as? NSCollectionViewFlowLayout)?.itemSize.width ?? currentSide
            item.configure(album, side: side, images: parent.images, isPlaying: album.id == parent.playingAlbumID, anyPlaying: parent.playingAlbumID != nil)
            #if DEBUG
            // -FinifyDemoHoverAll YES：所有封面都呈現 hover 狀態，截圖檢查 hover 效果
            if UserDefaults.standard.bool(forKey: "FinifyDemoHoverAll") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { item.debugForceHover() }
            }
            #endif
            item.onClick = { [weak self] in self?.parent.onOpen(album) }
            item.onDoubleClick = { [weak self] in self?.parent.onPlay(album) }
            item.menuProvider = { [weak self] in self?.menu(for: album) }
            return item
        }

        // 選取（方向鍵移動）只顯示焦點框；點一下打開專輯、雙擊或 Return 播放
        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            if let index = indexPaths.first?.item, parent.albums.indices.contains(index) {
                NSAccessibility.post(element: collectionView, notification: .announcementRequested,
                                     userInfo: [.announcement: "\(parent.albums[index].name), \(parent.albums[index].artistName)"])
            }
        }

        /// 依密度（列數）套用：封面邊長由可視高度決定，剛好填滿上下
        func applyDensity(_ density: WallDensity, animated: Bool) {
            let height = collection?.enclosingScrollView?.contentView.bounds.height ?? 0
            applySize(density.side(forHeight: height, bottomInset: parent.bottomInset), rows: density.rows, animated: animated)
        }

        func applySize(_ side: CGFloat, rows: Int?, animated: Bool) {
            currentSide = side
            currentRows = rows
            guard let collection, let layout = collection.collectionViewLayout as? WallRowsLayout else { return }
            layout.targetRows = rows
            // 封面牆：間距隨尺寸縮放，小尺寸幾乎無縫；上下留給頂部列與底部播放列
            let gap = max(2, (side * 0.025).rounded())
            layout.targetSide = side
            layout.minimumInteritemSpacing = gap
            layout.minimumLineSpacing = gap
            layout.sectionInset = NSEdgeInsets(top: WallDensity.topInset, left: 24, bottom: parent.bottomInset, right: 24)
            if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.28
                    collection.animator().collectionViewLayout?.invalidateLayout()
                }
            } else {
                layout.invalidateLayout()
            }
            for item in collection.visibleItems() { (item as? WallItem)?.updateSide(side) }
        }

        @objc func pinch(_ gesture: NSMagnificationGestureRecognizer) {
            switch gesture.state {
            case .began:
                isPinching = true
                motion.noteActivity()
                pinchStartSide = currentSide
            case .changed:
                let side = min(WallDensity.huge.side * 1.15, max(WallDensity.tiny.side * 0.85, pinchStartSide * (1 + gesture.magnification)))
                applySize(side, rows: nil, animated: false)
            default:
                isPinching = false
                // 放開時吸附到最接近的列數
                let height = collection?.enclosingScrollView?.contentView.bounds.height ?? 0
                let snapped = WallDensity.nearest(rows: max(1, height - WallDensity.topInset - parent.bottomInset) / max(1, currentSide))
                applyDensity(snapped, animated: true)
                if parent.density != snapped { parent.density = snapped }
            }
        }

        func refreshPlaying() {
            guard let collection else { return }
            for indexPath in collection.indexPathsForVisibleItems() {
                guard let item = collection.item(at: indexPath) as? WallItem, parent.albums.indices.contains(indexPath.item) else { continue }
                item.setPlaying(parent.albums[indexPath.item].id == parent.playingAlbumID, anyPlaying: parent.playingAlbumID != nil)
            }
        }

        func scrollToPlaying() {
            guard let id = parent.playingAlbumID, let index = parent.albums.firstIndex(where: { $0.id == id }) else { return }
            motion.noteActivity()
            collection?.animator().scrollToItems(at: [IndexPath(item: index, section: 0)], scrollPosition: .centeredHorizontally)
        }

        /// 輸入文字跳到第一張專輯名或藝人以此開頭的專輯（像 Finder 的 type-to-select）
        func jump(to prefix: String) {
            guard let collection, !prefix.isEmpty else { return }
            func matches(_ text: String) -> Bool {
                text.range(of: prefix, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
            }
            // 先比對目前排序依據的欄位（藝人或專輯名），找不到再比對另一個
            let primary: (Album) -> String = parent.typeToSelectByTitle ? { $0.name } : { $0.artistName }
            let secondary: (Album) -> String = parent.typeToSelectByTitle ? { $0.artistName } : { $0.name }
            let index = parent.albums.firstIndex { matches(primary($0)) } ?? parent.albums.firstIndex { matches(secondary($0)) }
            guard let index else { NSSound.beep(); return }
            let path = IndexPath(item: index, section: 0)
            collection.selectionIndexPaths = [path]
            collection.scrollToItems(at: [path], scrollPosition: .centeredHorizontally)
            self.collectionView(collection, didSelectItemsAt: [path])
        }

        func playSelected() {
            guard parent.acceptsKeyboard, let index = collection?.selectionIndexPaths.first?.item, parent.albums.indices.contains(index) else { return }
            parent.onPlay(parent.albums[index])
        }

        private func menu(for album: Album) -> NSMenu {
            let menu = NSMenu()
            menu.addItem(ClosureMenuItem("Play") { [weak self] in self?.parent.onPlay(album) })
            menu.addItem(ClosureMenuItem("Play Next") { [weak self] in self?.parent.onQueue(album, true) })
            menu.addItem(ClosureMenuItem("Add to Queue") { [weak self] in self?.parent.onQueue(album, false) })
            for item in parent.extraMenu?(album) ?? [] { menu.addItem(item) }
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Show Album") { [weak self] in self?.parent.onOpen(album) })
            return menu
        }
    }
}

/// Return 鍵播放選取的專輯
final class WallCollectionView: NSCollectionView {
    weak var coordinator: AlbumWallView.Coordinator?
    private var typed = ""
    private var lastTyped = Date.distantPast

    /// 出現時取得鍵盤焦點，方向鍵與 Return 才能直接使用（目前有文字輸入焦點時不搶）
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, !(window.firstResponder is NSText) else { return }
            window.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        coordinator?.motion.noteActivity()
        if event.keyCode == 36 || event.keyCode == 76 { coordinator?.playSelected(); return }
        // 還沒有選取時，第一次按方向鍵選取畫面上第一張
        let arrows: Set<UInt16> = [123, 124, 125, 126]
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        // 一般文字：累積 1 秒內輸入的字元，跳到符合的專輯
        if modifiers.isEmpty, let chars = event.characters, !chars.isEmpty,
           chars.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == " " }),
           !(chars == " " && typed.isEmpty) {
            if Date().timeIntervalSince(lastTyped) > 1 { typed = "" }
            typed += chars
            lastTyped = Date()
            coordinator?.jump(to: typed)
            return
        }
        if arrows.contains(event.keyCode), modifiers.isEmpty, selectionIndexPaths.isEmpty {
            let visible = visibleRect
            if let first = indexPathsForVisibleItems().sorted().first(where: {
                guard let frame = layoutAttributesForItem(at: $0)?.frame else { return false }
                return visible.contains(frame)
            }) {
                selectionIndexPaths = [first]
                scrollToItems(at: [first], scrollPosition: .nearestHorizontalEdge)
                delegate?.collectionView?(self, didSelectItemsAt: [first])
                return
            }
        }
        super.keyDown(with: event)
    }

    /// 在封面之間的空白處按住拖曳也能捲動
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        deselectAll(nil)
        trackPan(from: event, onClick: nil)
    }

    /// 按住滑鼠左右拖曳捲動；沒有移動超過幾點就視為點擊。放開時帶慣性
    func trackPan(from event: NSEvent, onClick: (() -> Void)?) {
        guard let window, let clip = enclosingScrollView?.contentView else { onClick?(); return }
        coordinator?.motion.noteActivity()
        coordinator?.motion.stopInertia()
        var last = event.locationInWindow
        var lastTime = event.timestamp
        var travelled: CGFloat = 0
        var velocity: CGFloat = 0
        var panning = false
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            let point = next.locationInWindow
            let dx = point.x - last.x
            travelled += abs(dx) + abs(point.y - last.y)
            if travelled > 4 { panning = true }
            if panning {
                scrollHorizontally(clip, by: -dx)
                let dt = max(next.timestamp - lastTime, 0.001)
                // 平滑速度，避免最後一個事件決定一切
                velocity = velocity * 0.6 + (-dx / CGFloat(dt)) * 0.4
            }
            last = point
            lastTime = next.timestamp
        }
        coordinator?.motion.noteActivity()
        if panning {
            coordinator?.motion.startInertia(velocity: velocity)
        } else {
            onClick?()
        }
    }

    func scrollHorizontally(_ clip: NSClipView, by delta: CGFloat) {
        let maxX = max(0, frame.width - clip.bounds.width)
        let x = min(max(0, clip.bounds.origin.x + delta), maxX)
        clip.scroll(to: NSPoint(x: x, y: clip.bounds.origin.y))
        enclosingScrollView?.reflectScrolledClipView(clip)
    }
}

/// 左右捲動的封面牆：依可用高度決定列數，封面填滿上下之間
final class WallRowsLayout: NSCollectionViewFlowLayout {
    var targetSide: CGFloat = 148
    /// 指定列數（一般情況）；nil 時依 targetSide 算（pinch 進行中）
    var targetRows: Int?

    override func prepare() {
        scrollDirection = .horizontal
        // 以可視區域（clip view）的高度計算；collection view 本身的高度由 layout 決定，不能拿來算
        if let height = collectionView?.enclosingScrollView?.contentView.bounds.height, height > 0 {
            let available = height - sectionInset.top - sectionInset.bottom
            let rows = targetRows ?? max(1, Int((available + minimumInteritemSpacing) / (targetSide + minimumInteritemSpacing)))
            let side = floor((available - CGFloat(rows - 1) * minimumInteritemSpacing) / CGFloat(rows))
            itemSize = NSSize(width: side, height: side)
        }
        super.prepare()
    }

    /// 版面上次計算時的可視高度；視窗高度改變時要重算列數
    fileprivate var preparedHeight: CGFloat = 0
}

/// 垂直的滑鼠滾輪與觸控板滑動也讓封面牆左右移動
final class WallScrollView: NSScrollView {
    var onUserScroll: (() -> Void)?

    // 不顯示捲軸：以拖曳、滾輪、漂移捲動（SwiftUI 會重設 scroller 設定，所以直接鎖住）
    override var hasHorizontalScroller: Bool {
        get { false }
        set {}
    }

    /// 視窗高度改變時重算封面牆的列數與尺寸
    override func tile() {
        super.tile()
        guard let layout = (documentView as? NSCollectionView)?.collectionViewLayout as? WallRowsLayout else { return }
        let height = contentView.bounds.height
        if height > 0, abs(height - layout.preparedHeight) > 0.5 {
            layout.preparedHeight = height
            layout.invalidateLayout()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        onUserScroll?()
        guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
              let wall = documentView as? WallCollectionView else {
            super.scrollWheel(with: event)
            return
        }
        // 滑鼠滾輪的 delta 是「行」，乘上一格的距離
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 24
        wall.scrollHorizontally(contentView, by: -delta)
    }
}

/// 封面牆的動態：拖曳放開後的慣性，以及滑鼠不在封面牆上時的緩慢漂移
@MainActor
final class WallMotion: NSObject {
    /// 漂移的最高速度（點／秒）
    static let driftSpeed: CGFloat = 22

    private weak var collection: WallCollectionView?
    private var link: CADisplayLink?
    private var monitor: Any?
    private var lastTick: CFTimeInterval = 0
    private var inertia: CGFloat = 0
    private var drift: CGFloat = 0
    private var direction: CGFloat = 1

    func attach(to collection: WallCollectionView) {
        self.collection = collection
        let link = collection.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        // 滑鼠移動、點擊、按鍵都算操作（只看這個視窗的事件）
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .magnify]) { [weak self] event in
            if event.window === self?.collection?.window { self?.noteActivity() }
            return event
        }
    }

    func detach() {
        link?.invalidate()
        link = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    func noteActivity() {
        drift = 0
    }

    func stopInertia() { inertia = 0 }

    func startInertia(velocity: CGFloat) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        inertia = max(-4000, min(4000, velocity))
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTick == 0 ? 1.0 / 60 : min(now - lastTick, 0.05)
        lastTick = now
        guard let collection, let clip = collection.enclosingScrollView?.contentView else { return }

        if abs(inertia) > 8 {
            collection.scrollHorizontally(clip, by: inertia * CGFloat(dt))
            inertia *= CGFloat(pow(0.92, dt * 60))
            return
        }
        inertia = 0

        // 滑鼠在封面牆上就停下來（速度歸零，再開始時重新緩緩加速）
        guard shouldDrift, !isMouseOverWall else {
            drift = 0
            return
        }
        let maxX = collection.frame.width - clip.bounds.width
        guard maxX > 0 else { return }
        // 到邊緣就慢慢反向；速度用緩動逐漸增加，開始時不會突然動起來
        let x = clip.bounds.origin.x
        if (direction > 0 && x >= maxX - 1) || (direction < 0 && x <= 1) {
            direction = -direction
            drift = 0
        }
        drift = min(Self.driftSpeed, drift + Self.driftSpeed * CGFloat(dt) / 3)
        collection.scrollHorizontally(clip, by: direction * drift * CGFloat(dt))
    }

    /// app 在背景時也漂移（例如邊工作邊放著封面牆），只要視窗看得到
    /// 滑鼠是否在封面牆的可視範圍內（頂部列與底部播放列也算，避免操作控制項時封面在底下移動）
    private var isMouseOverWall: Bool {
        guard let window = collection?.window else { return false }
        let point = window.mouseLocationOutsideOfEventStream
        return window.contentView?.bounds.contains(point) == true && NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) == window.windowNumber
    }

    private var shouldDrift: Bool {
        collection?.window?.occlusionState.contains(.visible) == true
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && (UserDefaults.standard.object(forKey: SettingsKey.wallDrift) as? Bool ?? true)
    }
}

final class WallItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("WallItem")
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?

    private let artwork = CALayer()
    /// 陰影畫在獨立 layer，artwork 本身保持裁切
    private let shadowLayer = CALayer()
    /// 沒有封面時顯示專輯名
    private let titleLayer = CATextLayer()
    /// hover：封面四周的白光與細白邊（不放大）
    private let glowLayer = CALayer()
    private let edgeLayer = CALayer()
    /// hover 時在封面下方顯示專輯與藝人
    private let captionGradient = CAGradientLayer()
    private let captionLayer = CATextLayer()
    private var task: Task<Void, Never>?
    private var albumID: String?
    private var isPlaying = false
    private var anyPlaying = false
    private var hovering = false
    private var tracking: NSTrackingArea?
    private weak var images: ImagePipeline?
    private var album: Album?
    private var side: CGFloat = 148

    override func loadView() {
        let view = WallItemView()
        view.wantsLayer = true
        view.item = self
        artwork.contentsGravity = .resizeAspectFill
        artwork.masksToBounds = true
        artwork.cornerCurve = .continuous
        shadowLayer.backgroundColor = NSColor.black.cgColor
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOffset = CGSize(width: 0, height: -10)
        shadowLayer.opacity = 0
        glowLayer.shadowColor = NSColor.white.cgColor
        glowLayer.shadowOffset = .zero
        glowLayer.shadowRadius = 18
        glowLayer.shadowOpacity = 0.85
        glowLayer.opacity = 0
        edgeLayer.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
        edgeLayer.borderWidth = 1.5
        edgeLayer.cornerCurve = .continuous
        edgeLayer.opacity = 0
        titleLayer.isWrapped = true
        titleLayer.truncationMode = .end
        titleLayer.alignmentMode = .left
        titleLayer.foregroundColor = NSColor(white: 0.85, alpha: 1).cgColor
        titleLayer.contentsScale = 2
        captionGradient.colors = [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.withAlphaComponent(0.85).cgColor]
        captionGradient.opacity = 0
        captionLayer.isWrapped = true
        captionLayer.truncationMode = .end
        captionLayer.foregroundColor = NSColor.white.cgColor
        captionLayer.contentsScale = 2
        view.layer?.addSublayer(glowLayer)
        view.layer?.addSublayer(shadowLayer)
        view.layer?.addSublayer(artwork)
        view.layer?.addSublayer(edgeLayer)
        artwork.addSublayer(titleLayer)
        artwork.addSublayer(captionGradient)
        captionGradient.addSublayer(captionLayer)
        view.layer?.masksToBounds = false
        self.view = view
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        artwork.frame = view.bounds
        artwork.cornerRadius = Radius.artwork(for: view.bounds.width)
        let inset = max(6, view.bounds.width * 0.07)
        titleLayer.frame = view.bounds.insetBy(dx: inset, dy: inset)
        titleLayer.fontSize = max(9, view.bounds.width * 0.085)
        titleLayer.font = NSFont.systemFont(ofSize: titleLayer.fontSize, weight: .semibold)
        let captionHeight = max(36, view.bounds.height * 0.42)
        captionGradient.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: captionHeight)
        captionLayer.fontSize = max(10, min(14, view.bounds.width * 0.075))
        captionLayer.font = NSFont.systemFont(ofSize: captionLayer.fontSize, weight: .semibold)
        captionLayer.frame = CGRect(x: inset, y: inset * 0.6, width: view.bounds.width - inset * 2, height: captionLayer.fontSize * 2.8)
        shadowLayer.frame = view.bounds
        shadowLayer.shadowPath = CGPath(rect: view.bounds.insetBy(dx: 2, dy: 2), transform: nil)
        glowLayer.frame = view.bounds
        glowLayer.shadowPath = CGPath(roundedRect: view.bounds, cornerWidth: artwork.cornerRadius, cornerHeight: artwork.cornerRadius, transform: nil)
        edgeLayer.frame = view.bounds
        edgeLayer.cornerRadius = artwork.cornerRadius
        CATransaction.commit()
    }

    func configure(_ album: Album, side: CGFloat, images: ImagePipeline?, isPlaying: Bool, anyPlaying: Bool) {
        task?.cancel()
        self.album = album
        self.images = images
        self.side = side
        albumID = album.id
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("\(album.name), \(album.artistName)")
        view.toolTip = "\(album.name) — \(album.artistName)"
        let caption = NSMutableAttributedString(string: album.name, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white])
        caption.append(NSAttributedString(string: "\n" + album.artistName, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white.withAlphaComponent(0.7)]))
        captionLayer.string = caption
        loadArtwork()
        setPlaying(isPlaying, anyPlaying: anyPlaying, animated: false)
    }

    func updateSide(_ side: CGFloat) {
        // 放大超過目前縮圖解析度時，換更大的縮圖
        guard ImagePipeline.bucket(Int(side * 2)) != ImagePipeline.bucket(Int(self.side * 2)) else { self.side = side; return }
        self.side = side
        loadArtwork()
    }

    private func loadArtwork() {
        task?.cancel()
        guard let album else { return }
        let pixels = Int(side * (view.window?.backingScaleFactor ?? 2))
        titleLayer.string = nil
        guard let ref = album.artwork, let images else {
            artwork.contents = nil
            artwork.backgroundColor = NSColor(hex: 0x10264B).cgColor
            titleLayer.contentsScale = view.window?.backingScaleFactor ?? 2
            titleLayer.string = "\(album.name)\n\(album.artistName)"
            return
        }
        if let hit = images.cached(ref, pixelSize: pixels) {
            artwork.contents = hit
            return
        }
        artwork.contents = ref.blurHash.flatMap { BlurHash.image($0) }
        artwork.backgroundColor = NSColor(hex: 0x0A1D3C).cgColor
        let id = album.id
        let bucket = ImagePipeline.bucket(pixels)
        task = Task { [weak self] in
            guard let image = await images.image(ref, pixelSize: pixels), !Task.isCancelled else { return }
            // 確認還是同一張專輯、同一個尺寸，避免較慢的小圖蓋掉清晰的大圖
            guard let self, self.albumID == id,
                  ImagePipeline.bucket(Int(self.side * (self.view.window?.backingScaleFactor ?? 2))) == bucket else { return }
            let fade = CABasicAnimation(keyPath: "contents")
            fade.duration = 0.2
            self.artwork.add(fade, forKey: "fade")
            self.artwork.contents = image
        }
    }

    func setPlaying(_ playing: Bool, anyPlaying: Bool, animated: Bool = true) {
        isPlaying = playing
        self.anyPlaying = anyPlaying
        applyState(animated: animated)
    }

    #if DEBUG
    fileprivate func debugForceHover() {
        hovering = true
        applyState(animated: false)
    }
    #endif

    fileprivate func setHovering(_ hovering: Bool) {
        // 一次只會有一張在 hover：捲動或漂移時可能漏掉 mouseExited，先清掉其他張，避免一整排停在放大狀態
        if hovering {
            for other in collectionView?.visibleItems() ?? [] where other !== self {
                if let item = other as? WallItem, item.hovering { item.hovering = false; item.applyState(animated: true) }
            }
        }
        self.hovering = hovering
        applyState(animated: true)
    }

    /// Currently Playing Elevation：放大、陰影、置頂；其他封面略為壓暗以拉開對比
    private func applyState(animated: Bool) {
        guard let layer = view.layer else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // hover 不放大，改用白光籠罩邊緣；正在播放的專輯仍浮起放大
        let scale: CGFloat = isPlaying ? 1.08 : 1
        let raised = isPlaying || hovering
        let zPosition: CGFloat = isPlaying ? 20 : (hovering ? 10 : 0)
        let duration = animated && !reduceMotion ? (raised ? 0.55 : 0.7) : 0
        CATransaction.begin()
        // 柔和：慢慢起步、長長收尾；縮回比放大更從容（原本 0.35 秒 easeOut 起步太急）
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.33, 0, 0.15, 1))
        // 浮起時立刻置頂；降下時等縮回原尺寸才放回原層，否則還在縮小時就被旁邊的封面突然蓋住。
        // completion block 只等之後加入的動畫，所以要在改 transform 之前設定
        if zPosition >= layer.zPosition || duration == 0 {
            layer.zPosition = zPosition
        } else {
            CATransaction.setCompletionBlock { [weak self] in
                guard let self, let layer = self.view.layer else { return }
                let current: CGFloat = self.isPlaying ? 20 : (self.hovering ? 10 : 0)
                if current == zPosition { layer.zPosition = zPosition }
            }
        }
        let bounds = view.bounds
        var transform = CATransform3DIdentity
        transform = CATransform3DTranslate(transform, bounds.midX, bounds.midY, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        transform = CATransform3DTranslate(transform, -bounds.midX, -bounds.midY, 0)
        layer.sublayerTransform = transform
        shadowLayer.opacity = isPlaying ? 1 : 0
        glowLayer.opacity = hovering ? 1 : 0
        edgeLayer.opacity = hovering ? 1 : 0
        // 專輯資訊一律點了才看（打開專輯面板），hover 只放大
        captionGradient.opacity = 0
        shadowLayer.shadowOpacity = isPlaying ? 0.7 : 0.5
        shadowLayer.shadowRadius = isPlaying ? 24 : 12
        artwork.opacity = anyPlaying && !isPlaying && !hovering ? 0.82 : 1
        CATransaction.commit()
    }

    override var isSelected: Bool {
        didSet {
            // 鍵盤焦點框
            artwork.borderWidth = isSelected ? 3 : 0
            artwork.borderColor = NSColor(hex: 0x2F6BFF).cgColor
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        task?.cancel()
        task = nil
        artwork.contents = nil
        hovering = false
        isPlaying = false
    }

    fileprivate func clicked() { onClick?() }
    fileprivate func doubleClicked() { onDoubleClick?() }
    fileprivate func contextMenu() -> NSMenu? { menuProvider?() }
}

private final class WallItemView: NSView {
    weak var item: WallItem?
    /// 單擊要等雙擊間隔過去才執行，否則雙擊的第一下會先打開專輯
    private var pendingClick: DispatchWorkItem?

    // .inVisibleRect 會自動跟著 view 的可見範圍，只要加一次。
    // 原本每次 updateTrackingAreas 都移除重建，捲動時每個 cell 都要重做（Instruments 佔 main thread 約 2%）
    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) { item?.setHovering(true) }
    override func mouseExited(with event: NSEvent) { item?.setHovering(false) }

    override func mouseDown(with event: NSEvent) {
        guard let wall = item?.collectionView as? WallCollectionView else { return }
        wall.window?.makeFirstResponder(wall)
        // 焦點框只給鍵盤操作用，滑鼠點擊不留選取
        wall.deselectAll(nil)
        pendingClick?.cancel()
        if event.clickCount >= 2 {
            item?.doubleClicked()
            return
        }
        // 按住拖曳是捲動；沒有拖曳才算點擊
        wall.trackPan(from: event) { [weak self] in
            let work = DispatchWorkItem { self?.item?.clicked() }
            self?.pendingClick = work
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? { item?.contextMenu() }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}
