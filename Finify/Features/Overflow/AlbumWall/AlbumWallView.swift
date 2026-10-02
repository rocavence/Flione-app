import AppKit
import SwiftUI

enum WallDensity: Int, CaseIterable, Sendable {
    case small, medium, large

    var side: CGFloat {
        switch self {
        case .small: 96
        case .medium: 148
        case .large: 220
        }
    }

    var label: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
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
    /// 捲動到正在播放的專輯；值改變時觸發
    var scrollToPlayingToken = 0

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
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
        scroll.contentInsets = NSEdgeInsets(top: 64, left: 0, bottom: 120, right: 0)

        let pinch = NSMagnificationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        collection.addGestureRecognizer(pinch)

        context.coordinator.collection = collection
        context.coordinator.applySize(density.side, animated: false)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let albumsChanged = coordinator.parent.albums.map(\.id) != albums.map(\.id)
        let densityChanged = coordinator.parent.density != density
        let playingChanged = coordinator.parent.playingAlbumID != playingAlbumID
        let scrollRequested = coordinator.parent.scrollToPlayingToken != scrollToPlayingToken
        coordinator.parent = self
        if albumsChanged { coordinator.collection?.reloadData() }
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
        private var currentSide: CGFloat = 148

        init(parent: AlbumWallView) { self.parent = parent }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.albums.count
        }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: WallItem.identifier, for: indexPath) as! WallItem
            let album = parent.albums[indexPath.item]
            item.configure(album, side: currentSide, images: parent.images, isPlaying: album.id == parent.playingAlbumID, anyPlaying: parent.playingAlbumID != nil)
            item.onDoubleClick = { [weak self] in self?.parent.onPlay(album) }
            item.menuProvider = { [weak self] in self?.menu(for: album) }
            return item
        }

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            guard let index = indexPaths.first?.item, parent.albums.indices.contains(index) else { return }
            parent.onOpen(parent.albums[index])
            collectionView.deselectItems(at: indexPaths)
        }

        func applySize(_ side: CGFloat, animated: Bool) {
            currentSide = side
            guard let collection, let layout = collection.collectionViewLayout as? NSCollectionViewFlowLayout else { return }
            // 封面牆：間距隨尺寸縮放，小尺寸幾乎無縫
            let gap = max(2, (side * 0.025).rounded())
            layout.itemSize = NSSize(width: side, height: side)
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
                let side = min(WallDensity.large.side * 1.2, max(WallDensity.small.side * 0.8, pinchStartSide * (1 + gesture.magnification)))
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

        func playSelected() {
            guard let index = collection?.selectionIndexPaths.first?.item, parent.albums.indices.contains(index) else { return }
            parent.onPlay(parent.albums[index])
        }

        private func menu(for album: Album) -> NSMenu {
            let menu = NSMenu()
            menu.addItem(ClosureMenuItem("Play") { [weak self] in self?.parent.onPlay(album) })
            menu.addItem(ClosureMenuItem("Play Next") { [weak self] in self?.parent.onQueue(album, true) })
            menu.addItem(ClosureMenuItem("Add to Queue") { [weak self] in self?.parent.onQueue(album, false) })
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Show Album") { [weak self] in self?.parent.onOpen(album) })
            return menu
        }
    }
}

/// Return 鍵播放選取的專輯
final class WallCollectionView: NSCollectionView {
    weak var coordinator: AlbumWallView.Coordinator?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { coordinator?.playSelected(); return }
        super.keyDown(with: event)
    }
}

final class WallItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("WallItem")
    var onDoubleClick: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?

    private let artwork = CALayer()
    /// 陰影畫在獨立 layer，artwork 本身保持裁切
    private let shadowLayer = CALayer()
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
        view.layer?.addSublayer(shadowLayer)
        view.layer?.addSublayer(artwork)
        view.layer?.masksToBounds = false
        self.view = view
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        artwork.frame = view.bounds
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
        guard let album else { return }
        let pixels = Int(side * (view.window?.backingScaleFactor ?? 2))
        guard let ref = album.artwork, let images else {
            artwork.contents = nil
            artwork.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
            return
        }
        if let hit = images.cached(ref, pixelSize: pixels) {
            artwork.contents = hit
            return
        }
        artwork.contents = ref.blurHash.flatMap { BlurHash.image($0) }
        artwork.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        let id = album.id
        task = Task { [weak self] in
            guard let image = await images.image(ref, pixelSize: pixels), !Task.isCancelled else { return }
            guard let self, self.albumID == id else { return }
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
        shadowLayer.shadowOpacity = isPlaying ? 0.7 : 0.5
        shadowLayer.shadowRadius = isPlaying ? 24 : 12
        artwork.opacity = anyPlaying && !isPlaying && !hovering ? 0.82 : 1
        CATransaction.commit()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        task?.cancel()
        task = nil
        artwork.contents = nil
        hovering = false
        isPlaying = false
    }

    fileprivate func doubleClicked() { onDoubleClick?() }
    fileprivate func contextMenu() -> NSMenu? { menuProvider?() }
}

private final class WallItemView: NSView {
    weak var item: WallItem?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { item?.setHovering(true) }
    override func mouseExited(with event: NSEvent) { item?.setHovering(false) }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { item?.doubleClicked(); return }
        super.mouseDown(with: event)
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
