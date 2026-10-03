import AppKit
import SwiftUI

/// Library 的專輯格線，cell 為純 AppKit。
/// 原本用 NSHostingView 包 SwiftUI 卡片，每次重用 cell 都要重建整個 SwiftUI 圖，1360 寬時捲動明顯卡頓（Instruments 實測）。
struct LibraryAlbumGrid: NSViewRepresentable {
    let albums: [Album]
    let app: AppEnvironment
    let onOpen: (Album) -> Void
    let onPlay: (Album) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = AdaptiveGridLayout()
        layout.minItemWidth = 156
        layout.captionHeight = 48
        layout.minimumInteritemSpacing = Spacing.s20
        layout.minimumLineSpacing = Spacing.s24
        layout.sectionInset = NSEdgeInsets(top: 0, left: Spacing.s32, bottom: Spacing.s32, right: Spacing.s32)

        let collection = NSCollectionView()
        collection.collectionViewLayout = layout
        collection.dataSource = context.coordinator
        collection.delegate = context.coordinator
        collection.backgroundColors = [.clear]
        collection.register(LibraryAlbumItem.self, forItemWithIdentifier: LibraryAlbumItem.identifier)
        // 可拖曳到佇列面板（以 finify-album:// URL 傳遞）
        collection.setDraggingSourceOperationMask(.copy, forLocal: true)
        // NSCollectionView 只有在可選取時才會開始拖曳；選取本身不顯示，點擊由 cell 的 mouseUp 處理
        collection.isSelectable = true
        collection.setAccessibilityLabel("Albums")

        let scroll = NSScrollView()
        scroll.documentView = collection
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        context.coordinator.collection = collection
        context.coordinator.observePlayback()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let changed = coordinator.parent.albums != albums
        coordinator.parent = self
        if changed { coordinator.collection?.reloadData() }
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var parent: LibraryAlbumGrid
        weak var collection: NSCollectionView?
        private var playingAlbumID: String?
        private var isPlaying = false

        init(parent: LibraryAlbumGrid) { self.parent = parent }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.albums.count
        }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: LibraryAlbumItem.identifier, for: indexPath) as! LibraryAlbumItem
            let album = parent.albums[indexPath.item]
            let width = (collectionView.collectionViewLayout as? NSCollectionViewFlowLayout)?.itemSize.width ?? 168
            item.configure(album, images: parent.app.images, width: width, playing: album.id == playingAlbumID, isPlaying: isPlaying)
            item.onOpen = { [weak self] in self?.parent.onOpen(album) }
            item.onPlay = { [weak self] in
                guard let self else { return }
                if album.id == self.playingAlbumID { self.parent.app.player.togglePlayPause() } else { self.parent.onPlay(album) }
            }
            item.menuProvider = { [weak self] in self?.menu(for: album) }
            return item
        }

        func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool { true }

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            collectionView.deselectItems(at: indexPaths)
        }

        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
            guard parent.albums.indices.contains(indexPath.item) else { return nil }
            return DragPayload.album(parent.albums[indexPath.item].id) as NSURL
        }

        /// 正在播放的專輯改變時，只更新看得到的 cell
        func observePlayback() {
            withObservationTracking {
                playingAlbumID = parent.app.player.currentTrack?.albumID
                isPlaying = parent.app.player.isPlaying
            } onChange: { [weak self] in
                Task { @MainActor in
                    self?.observePlayback()
                    self?.refreshPlaying()
                }
            }
        }

        private func refreshPlaying() {
            guard let collection else { return }
            for indexPath in collection.indexPathsForVisibleItems() where parent.albums.indices.contains(indexPath.item) {
                let album = parent.albums[indexPath.item]
                (collection.item(at: indexPath) as? LibraryAlbumItem)?.setPlaying(album.id == playingAlbumID, isPlaying: isPlaying)
            }
        }

        private func menu(for album: Album) -> NSMenu {
            let app = parent.app
            let menu = NSMenu()
            menu.addItem(ClosureMenuItem("Play") { [weak self] in self?.parent.onPlay(album) })
            menu.addItem(ClosureMenuItem("Play Next") {
                Task { if let tracks = try? await app.repository?.tracks(inAlbum: album.id) { app.player.playNext(tracks) } }
            })
            menu.addItem(ClosureMenuItem("Add to Queue") {
                Task { if let tracks = try? await app.repository?.tracks(inAlbum: album.id) { app.player.addToQueue(tracks) } }
            })
            for item in app.albumMenuItems(for: album) { menu.addItem(item) }
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Open Album") { [weak self] in self?.parent.onOpen(album) })
            return menu
        }
    }
}

final class LibraryAlbumItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("LibraryAlbumItem")
    var onOpen: (() -> Void)?
    var onPlay: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?

    private let artwork = CALayer()
    private let fallbackTitle = CATextLayer()
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private let playButton = NSButton()
    private var task: Task<Void, Never>?
    private var album: Album?
    private weak var images: ImagePipeline?
    private var hovering = false
    private var playing = false
    private var isPlaying = false
    /// 由版面傳入；新建立的 cell 在 configure 時 bounds 還是 0
    private var itemWidth: CGFloat = 168

    override func loadView() {
        let view = LibraryAlbumItemView()
        view.item = self
        view.wantsLayer = true
        view.layer?.masksToBounds = false

        artwork.contentsGravity = .resizeAspectFill
        artwork.masksToBounds = true
        artwork.cornerCurve = .continuous
        artwork.borderWidth = 0.5
        fallbackTitle.isWrapped = true
        fallbackTitle.truncationMode = .end
        fallbackTitle.contentsScale = 2
        artwork.addSublayer(fallbackTitle)
        view.layer?.addSublayer(artwork)

        for field in [titleField, subtitleField] {
            field.lineBreakMode = .byTruncatingTail
            field.maximumNumberOfLines = 1
            view.addSubview(field)
        }
        titleField.font = .systemFont(ofSize: 14, weight: .medium)
        subtitleField.font = .systemFont(ofSize: 11)

        playButton.isBordered = false
        playButton.wantsLayer = true
        playButton.layer?.cornerRadius = 22
        playButton.imageScaling = .scaleProportionallyDown
        playButton.target = self
        playButton.action = #selector(playTapped)
        playButton.isHidden = true
        playButton.setAccessibilityElement(false)
        view.addSubview(playButton)

        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        self.view = view
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let width = view.bounds.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // AppKit 預設 y 軸向上：封面在上方，文字在下方
        artwork.frame = CGRect(x: 0, y: view.bounds.height - width, width: width, height: width)
        artwork.cornerRadius = Radius.artwork(for: width)
        let inset = width * 0.07
        fallbackTitle.frame = CGRect(x: inset, y: inset, width: width - inset * 2, height: width * 0.4)
        view.layer?.shadowPath = CGPath(roundedRect: artwork.frame, cornerWidth: artwork.cornerRadius, cornerHeight: artwork.cornerRadius, transform: nil)
        CATransaction.commit()
        titleField.frame = CGRect(x: 0, y: view.bounds.height - width - 26, width: width, height: 18)
        subtitleField.frame = CGRect(x: 0, y: view.bounds.height - width - 42, width: width, height: 15)
        playButton.frame = CGRect(x: width - 52, y: view.bounds.height - width + 8, width: 44, height: 44)
    }

    func configure(_ album: Album, images: ImagePipeline?, width: CGFloat, playing: Bool, isPlaying: Bool) {
        itemWidth = width
        task?.cancel()
        self.album = album
        self.images = images
        titleField.stringValue = album.name
        subtitleField.stringValue = album.artistName
        view.setAccessibilityLabel("\(album.name), \(album.artistName)")
        self.playing = playing
        self.isPlaying = isPlaying
        applyColors()
        loadArtwork()
        applyState()
    }

    func setPlaying(_ playing: Bool, isPlaying: Bool) {
        self.playing = playing
        self.isPlaying = isPlaying
        applyColors()
        applyState()
    }

    fileprivate func setHovering(_ hovering: Bool) {
        self.hovering = hovering
        applyState()
    }

    /// 深淺色切換時由 view 呼叫
    fileprivate func applyColors() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            titleField.textColor = playing ? NSColor(FinifyColor.orange) : NSColor(FinifyColor.ink)
            // 正在播放的標題散發橘色微光（與 SwiftUI 的 finifyGlow 一致）
            titleField.wantsLayer = true
            titleField.shadow = playing ? {
                let glow = NSShadow()
                glow.shadowColor = NSColor(FinifyColor.orange).withAlphaComponent(0.55)
                glow.shadowBlurRadius = 4
                glow.shadowOffset = .zero
                return glow
            }() : nil
            subtitleField.textColor = NSColor(FinifyColor.muted)
            artwork.backgroundColor = NSColor(FinifyColor.surface).cgColor
            artwork.borderColor = NSColor(FinifyColor.ink).withAlphaComponent(0.06).cgColor
            fallbackTitle.foregroundColor = NSColor(FinifyColor.ink).withAlphaComponent(0.85).cgColor
            playButton.layer?.backgroundColor = NSColor(FinifyColor.primary).cgColor
            playButton.contentTintColor = NSColor(FinifyColor.onPrimary)
        }
    }

    private func applyState() {
        playButton.isHidden = !(hovering || playing)
        playButton.image = NSImage(named: playing && isPlaying ? "Reicon/pause.filled" : "Reicon/play.filled")
        // 按鈕只在 hover 時出現；VoiceOver 改用 cell 上的自訂動作
        view.setAccessibilityCustomActions([NSAccessibilityCustomAction(name: playing && isPlaying ? "Pause" : "Play") { [weak self] in
            self?.onPlay?()
            return true
        }])
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        CATransaction.begin()
        CATransaction.setAnimationDuration(reduceMotion ? 0 : 0.15)
        // 陰影畫在外層 view（artwork 本身要裁切圓角）
        let elevated = hovering || playing
        view.layer?.shadowColor = NSColor.black.cgColor
        view.layer?.shadowOpacity = elevated ? (playing ? 0.45 : 0.28) : 0.18
        view.layer?.shadowRadius = elevated ? (playing ? 14 : 8) : 4
        view.layer?.shadowOffset = CGSize(width: 0, height: elevated ? -8 : -4)
        CATransaction.commit()
    }

    private func loadArtwork() {
        guard let album else { return }
        fallbackTitle.string = nil
        let scale = view.window?.backingScaleFactor ?? 2
        let pixels = Int(itemWidth * scale)
        guard let ref = album.artwork, let images else {
            artwork.contents = nil
            fallbackTitle.fontSize = 15
            fallbackTitle.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
            fallbackTitle.string = "\(album.name)\n\(album.artistName)"
            return
        }
        if let hit = images.cached(ref, pixelSize: pixels) {
            artwork.contents = hit
            return
        }
        artwork.contents = ref.blurHash.flatMap { BlurHash.image($0) }
        let id = album.id
        task = Task { [weak self] in
            guard let image = await images.image(ref, pixelSize: pixels), !Task.isCancelled else { return }
            guard let self, self.album?.id == id else { return }
            let fade = CABasicAnimation(keyPath: "contents")
            fade.duration = 0.2
            self.artwork.add(fade, forKey: "fade")
            self.artwork.contents = image
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        task?.cancel()
        task = nil
        artwork.contents = nil
        hovering = false
    }

    @objc private func playTapped() { onPlay?() }
    fileprivate func clicked() { onOpen?() }
    fileprivate func contextMenu() -> NSMenu? { menuProvider?() }
}

private final class LibraryAlbumItemView: NSView {
    weak var item: LibraryAlbumItem?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        item?.applyColors()
    }

    // .inVisibleRect 會自動跟著 view 的可見範圍，只要加一次。
    // 原本每次 updateTrackingAreas 都移除重建，捲動時每個 cell 都要重做（Instruments 佔 main thread 約 2%）
    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) { item?.setHovering(true) }
    override func mouseExited(with event: NSEvent) { item?.setHovering(false) }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        // 拖曳後放開不算點擊
        if event.clickCount == 1, bounds.contains(convert(event.locationInWindow, from: nil)) { item?.clicked() }
    }

    override func menu(for event: NSEvent) -> NSMenu? { item?.contextMenu() }

    override func accessibilityPerformPress() -> Bool {
        item?.clicked()
        return true
    }
}
