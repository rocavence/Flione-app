import AppKit
import SwiftUI

/// 大量項目的格線：NSCollectionView 負責 cell 重用與捲動，cell 內容仍是 SwiftUI。
/// SwiftUI 的 LazyVGrid 在上千個項目時捲動會明顯掉 frame（見 docs/spikes/S3-album-wall.md），所以 Library 改用這個。
/// NSHostingView 不繼承外層 environment，呼叫端在 `cell` 裡自行注入。
struct CollectionGrid<Item: Identifiable, Cell: View>: NSViewRepresentable where Item.ID: Hashable {
    let items: [Item]
    /// 每格最小寬度；實際寬度依可用寬度平均分配
    var minItemWidth: CGFloat = 156
    /// 封面以外的高度（標題、副標題）
    var captionHeight: CGFloat = 44
    var spacing: CGFloat = Spacing.s20
    var lineSpacing: CGFloat = Spacing.s24
    var insets = NSEdgeInsets(top: 0, left: Spacing.s32, bottom: Spacing.s32, right: Spacing.s32)
    let cell: (Item) -> Cell

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = AdaptiveGridLayout()
        layout.minItemWidth = minItemWidth
        layout.captionHeight = captionHeight
        layout.minimumInteritemSpacing = spacing
        layout.minimumLineSpacing = lineSpacing
        layout.sectionInset = insets

        let collection = NSCollectionView()
        collection.collectionViewLayout = layout
        collection.dataSource = context.coordinator
        collection.backgroundColors = [.clear]
        collection.register(HostingItem.self, forItemWithIdentifier: HostingItem.identifier)

        let scroll = NSScrollView()
        scroll.documentView = collection
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        context.coordinator.collection = collection
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let changed = coordinator.parent.items.map(\.id) != items.map(\.id)
        coordinator.parent = self
        if changed {
            coordinator.collection?.reloadData()
        } else {
            // 項目相同時只更新看得到的 cell（例如正在播放的狀態）
            coordinator.refreshVisible()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource {
        var parent: CollectionGrid
        weak var collection: NSCollectionView?

        init(parent: CollectionGrid) { self.parent = parent }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.items.count
        }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: HostingItem.identifier, for: indexPath) as! HostingItem
            item.set(AnyView(parent.cell(parent.items[indexPath.item])))
            return item
        }

        func refreshVisible() {
            guard let collection else { return }
            for indexPath in collection.indexPathsForVisibleItems() where parent.items.indices.contains(indexPath.item) {
                (collection.item(at: indexPath) as? HostingItem)?.set(AnyView(parent.cell(parent.items[indexPath.item])))
            }
        }
    }
}

/// 依可用寬度決定欄數，每欄平均分配寬度
final class AdaptiveGridLayout: NSCollectionViewFlowLayout {
    var minItemWidth: CGFloat = 156
    var captionHeight: CGFloat = 44

    override func prepare() {
        if let width = collectionView?.enclosingScrollView?.contentSize.width ?? collectionView?.bounds.width, width > 0 {
            let available = width - sectionInset.left - sectionInset.right
            let columns = max(1, Int((available + minimumInteritemSpacing) / (minItemWidth + minimumInteritemSpacing)))
            let itemWidth = floor((available - CGFloat(columns - 1) * minimumInteritemSpacing) / CGFloat(columns))
            itemSize = NSSize(width: itemWidth, height: itemWidth + captionHeight)
        }
        super.prepare()
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        newBounds.width != collectionView?.bounds.width
    }
}

final class HostingItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("HostingItem")
    private var host: NSHostingView<AnyView>?

    override func loadView() {
        view = NSView()
    }

    func set(_ content: AnyView) {
        if let host {
            host.rootView = content
        } else {
            let host = NSHostingView(rootView: content)
            host.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                host.topAnchor.constraint(equalTo: view.topAnchor),
                host.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            self.host = host
        }
    }
}
