import AppKit
import SwiftUI

enum WallDensity: Int, CaseIterable, Sendable {
    case tiny, small, medium, large, huge

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

    /// pinch 結束時吸附到最接近的 density
    static func nearest(to side: CGFloat) -> WallDensity {
        allCases.min { abs($0.side - side) < abs($1.side - side) }!
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

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        // 依可用寬度調整封面尺寸，讓每列剛好填滿，封面之間維持細縫
        let layout = AdaptiveGridLayout()
        layout.captionHeight = 0
        let collection = WallCollectionView()
        collection.collectionViewLayout = layout
        collection.dataSource = context.coordinator
        collection.delegate = context.coordinator
        collection.isSelectable = true
        collection.backgroundColors = [.clear]
        collection.register(WallItem.self, forItemWithIdentifier: WallItem.identifier)
        collection.coordinator = context.coordinator
        collection.setAccessibilityLabel("Album wall")

        let scroll = NSScrollView()
        scroll.documentView = collection
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 60, left: 0, bottom: 120, right: 0)

        let pinch = NSMagnificationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        collection.addGestureRecognizer(pinch)

        context.coordinator.collection = collection
        context.coordinator.applySize(density.side, animated: false)
        // 有 content inset 時，初始位置要捲到 inset 之上，第一列才不會被頂部列擋住
        scroll.contentView.scroll(to: NSPoint(x: 0, y: -scroll.contentInsets.top))
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let albumsChanged = coordinator.parent.albums.map(\.id) != albums.map(\.id)
        // binding 讀的是即時值，不能拿舊的 parent 比；改與目前實際尺寸比較
        let densityChanged = coordinator.currentSide != density.side
        let playingChanged = coordinator.parent.playingAlbumID != playingAlbumID
        let scrollRequested = coordinator.parent.scrollToPlayingToken != scrollToPlayingToken
        coordinator.parent = self
        if albumsChanged {
            // 排序或內容改變後，同一個位置已是另一張專輯
            coordinator.collection?.deselectAll(nil)
            coordinator.collection?.reloadData()
        }
        if densityChanged && !coordinator.isPinching { coordinator.applySize(density.side, animated: true) }
        if playingChanged { coordinator.refreshPlaying() }
        if scrollRequested { coordinator.scrollToPlaying() }
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var parent: AlbumWallView
        weak var collection: NSCollectionView?
        var isPinching = false
        private var pinchStartSide: CGFloat = 148
        private(set) var currentSide: CGFloat = 148

        init(parent: AlbumWallView) { self.parent = parent }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.albums.count
        }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: WallItem.identifier, for: indexPath) as! WallItem
            let album = parent.albums[indexPath.item]
            item.configure(album, side: currentSide, images: parent.images, isPlaying: album.id == parent.playingAlbumID, anyPlaying: parent.playingAlbumID != nil)
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

        func applySize(_ side: CGFloat, animated: Bool) {
            currentSide = side
            guard let collection, let layout = collection.collectionViewLayout as? AdaptiveGridLayout else { return }
            // 封面牆：間距隨尺寸縮放，小尺寸幾乎無縫
            let gap = max(2, (side * 0.025).rounded())
            layout.minItemWidth = side
            layout.minimumInteritemSpacing = gap
            layout.minimumLineSpacing = gap
            layout.sectionInset = NSEdgeInsets(top: gap, left: 24, bottom: gap, right: 24)
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
                pinchStartSide = currentSide
            case .changed:
                let side = min(WallDensity.huge.side * 1.15, max(WallDensity.tiny.side * 0.85, pinchStartSide * (1 + gesture.magnification)))
                applySize(side, animated: false)
            default:
                isPinching = false
                let snapped = WallDensity.nearest(to: currentSide)
                applySize(snapped.side, animated: true)
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
            collection?.animator().scrollToItems(at: [IndexPath(item: index, section: 0)], scrollPosition: .centeredVertically)
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
            collection.scrollToItems(at: [path], scrollPosition: .centeredVertically)
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
            // 扣掉頂部列與底部播放列擋住的範圍
            var visible = visibleRect
            if let insets = enclosingScrollView?.contentInsets {
                visible.origin.y += insets.top
                visible.size.height -= insets.top + insets.bottom
            }
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
        artwork.cornerRadius = 2
        shadowLayer.backgroundColor = NSColor.black.cgColor
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOffset = CGSize(width: 0, height: -10)
        shadowLayer.opacity = 0
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
        view.layer?.addSublayer(shadowLayer)
        view.layer?.addSublayer(artwork)
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
            artwork.backgroundColor = NSColor(white: 0.14, alpha: 1).cgColor
            titleLayer.contentsScale = view.window?.backingScaleFactor ?? 2
            titleLayer.string = "\(album.name)\n\(album.artistName)"
            return
        }
        if let hit = images.cached(ref, pixelSize: pixels) {
            artwork.contents = hit
            return
        }
        artwork.contents = ref.blurHash.flatMap { BlurHash.image($0) }
        artwork.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
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

    fileprivate func setHovering(_ hovering: Bool) {
        self.hovering = hovering
        applyState(animated: true)
    }

    /// Currently Playing Elevation：放大、陰影、置頂；其他封面略為壓暗以拉開對比
    private func applyState(animated: Bool) {
        guard let layer = view.layer else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let scale: CGFloat = isPlaying ? 1.08 : (hovering ? 1.04 : 1)
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated && !reduceMotion ? 0.35 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        let bounds = view.bounds
        var transform = CATransform3DIdentity
        transform = CATransform3DTranslate(transform, bounds.midX, bounds.midY, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        transform = CATransform3DTranslate(transform, -bounds.midX, -bounds.midY, 0)
        layer.sublayerTransform = transform
        layer.zPosition = isPlaying ? 20 : (hovering ? 10 : 0)
        shadowLayer.opacity = isPlaying || hovering ? 1 : 0
        // 小尺寸（Tiny／Small）封面太小，不顯示文字，只靠 tooltip
        captionGradient.opacity = hovering && bounds.width >= 120 && titleLayer.string == nil ? 1 : 0
        shadowLayer.shadowOpacity = isPlaying ? 0.7 : 0.5
        shadowLayer.shadowRadius = isPlaying ? 24 : 12
        artwork.opacity = anyPlaying && !isPlaying && !hovering ? 0.82 : 1
        CATransaction.commit()
    }

    override var isSelected: Bool {
        didSet {
            // 鍵盤焦點框
            artwork.borderWidth = isSelected ? 3 : 0
            artwork.borderColor = NSColor(hex: 0xFF6A3D).cgColor
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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { item?.setHovering(true) }
    override func mouseExited(with event: NSEvent) { item?.setHovering(false) }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // 焦點框只給鍵盤操作用，滑鼠點擊不留選取
        item?.collectionView?.deselectAll(nil)
        pendingClick?.cancel()
        if event.clickCount >= 2 {
            item?.doubleClicked()
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.item?.clicked() }
        pendingClick = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
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
