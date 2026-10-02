import AppKit
import SwiftUI

/// 方案 B：NSCollectionView 包進 SwiftUI，cell 重用由 AppKit 管理
struct AppKitWall: NSViewRepresentable {
    let albums: [Album]
    let density: Density
    let pipeline: ArtworkPipeline

    func makeCoordinator() -> Coordinator { Coordinator(albums: albums, pipeline: pipeline) }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let collection = NSCollectionView()
        collection.collectionViewLayout = layout
        collection.dataSource = context.coordinator
        collection.register(WallItem.self, forItemWithIdentifier: WallItem.identifier)
        collection.backgroundColors = [.clear]

        let scroll = NSScrollView()
        scroll.documentView = collection
        scroll.hasVerticalScroller = true
        context.coordinator.collection = collection
        apply(density, to: context.coordinator)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard context.coordinator.density != density else { return }
        apply(density, to: context.coordinator)
    }

    private func apply(_ density: Density, to coordinator: Coordinator) {
        coordinator.density = density
        guard let collection = coordinator.collection,
              let layout = collection.collectionViewLayout as? NSCollectionViewFlowLayout else { return }
        layout.itemSize = NSSize(width: density.side, height: density.side)
        collection.reloadData()
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource {
        let albums: [Album]
        let pipeline: ArtworkPipeline
        var density: Density = .medium
        weak var collection: NSCollectionView?

        init(albums: [Album], pipeline: ArtworkPipeline) {
            self.albums = albums
            self.pipeline = pipeline
        }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            albums.count
        }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: WallItem.identifier, for: indexPath) as! WallItem
            item.configure(albums[indexPath.item], px: density.pixelSize, pipeline: pipeline)
            return item
        }
    }
}

final class WallItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("WallItem")
    private var task: Task<Void, Never>?
    private var albumID = -1

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 4
        view.layer?.masksToBounds = true
        view.layer?.contentsGravity = .resizeAspectFill
    }

    func configure(_ album: Album, px: Int, pipeline: ArtworkPipeline) {
        task?.cancel()
        albumID = album.id
        view.layer?.backgroundColor = NSColor(hue: album.placeholderHue, saturation: 0.4, brightness: 0.5, alpha: 1).cgColor
        if let hit = pipeline.cached(album, px: px) {
            view.layer?.contents = hit
            return
        }
        view.layer?.contents = nil
        let id = album.id
        task = Task { [weak self] in
            let image = await pipeline.load(album, px: px)
            guard let self, !Task.isCancelled, self.albumID == id else { return }
            self.view.layer?.contents = image
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        task?.cancel()
        task = nil
        view.layer?.contents = nil
    }
}
