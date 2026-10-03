import SwiftUI

/// 登入後選擇體驗：Standard、Infinity 或 Cover Flow。三者是平級的 App 入口。
struct ModePickerView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        @Bindable var app = app
        VStack(spacing: Spacing.s40) {
            VStack(spacing: Spacing.s8) {
                Text("Choose your experience")
                    .finifyFont(.title)
                    .foregroundStyle(FinifyColor.ink)
                Text("You can switch anytime with ⌘1, ⌘2, and ⌘3, or from the top-right corner.")
                    .finifyFont(.body)
                    .foregroundStyle(FinifyColor.muted)
            }
            HStack(spacing: Spacing.s24) {
                ModeCard(mode: .standard, title: "Modern", subtitle: "Presence. Drift through your music,\nalways knowing where you are.") { app.viewMode = .standard }
                ModeCard(mode: .infinity, title: "Infinity", subtitle: "Depth. An ocean of albums with no edge;\nkeep swimming and discover.") { app.viewMode = .infinity }
                ModeCard(mode: .coverFlow, title: "Cover Flow", subtitle: "Visual. Glide between floating covers\nand pick what draws you in.") { app.viewMode = .coverFlow }
            }
            Toggle("Remember my choice", isOn: $app.rememberMode)
                .toggleStyle(.checkbox)
                .finifyFont(.body)
                .foregroundStyle(FinifyColor.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FinifyColor.paper)
        .task { await app.library.refreshIfNeeded() }
    }
}

private struct ModeCard: View {
    let mode: ViewMode
    let title: String
    let subtitle: String
    let choose: () -> Void

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 0) {
                preview
                    .frame(width: 280, height: 190)
                    .clipped()
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    Text(title).finifyFont(.heading).foregroundStyle(FinifyColor.ink)
                    Text(subtitle).finifyFont(.caption).foregroundStyle(FinifyColor.muted).fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.s20)
            }
            .frame(width: 280)
            .background(FinifyColor.elevated, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .strokeBorder(hovering ? FinifyColor.accent.opacity(0.6) : FinifyColor.hairline, lineWidth: 1)
            }
            .finifyShadow(hovering ? FinifyShadow.artworkHover : FinifyShadow.artwork)
            .scaleEffect(hovering && !reduceMotion ? 1.01 : 1)
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
        .accessibilityLabel("\(title): \(subtitle)")
    }

    private var sample: [Album] { Array(app.library.albums.filter { $0.artwork != nil }.prefix(40)) }

    @ViewBuilder
    private var preview: some View {
        switch mode {
        case .standard:
            // 示意：資訊架構清楚的清單與卡片
            VStack(alignment: .leading, spacing: Spacing.s12) {
                RoundedRectangle(cornerRadius: 2).fill(FinifyColor.ink.opacity(0.8)).frame(width: 110, height: 10)
                HStack(spacing: Spacing.s8) {
                    ForEach(Array(sample.prefix(4)), id: \.id) { album in
                        ArtworkView(artwork: album.artwork, elevation: .none)
                    }
                }
                ForEach(0..<4, id: \.self) { i in
                    HStack(spacing: Spacing.s8) {
                        RoundedRectangle(cornerRadius: 2).fill(FinifyColor.faint.opacity(0.5)).frame(width: 12, height: 6)
                        RoundedRectangle(cornerRadius: 2).fill(FinifyColor.muted.opacity(0.5)).frame(width: CGFloat(120 - i * 14), height: 6)
                        Spacer()
                        RoundedRectangle(cornerRadius: 2).fill(FinifyColor.faint.opacity(0.5)).frame(width: 24, height: 6)
                    }
                }
            }
            .padding(Spacing.s20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(FinifyColor.paper)
        case .coverFlow:
            CoverFlowPreview(albums: Array(sample.prefix(5)))
        case .infinity:
            // 示意：封面牆
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 8)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(sample, id: \.id) { album in
                    ArtworkView(artwork: album.artwork, cornerRadius: 2, elevation: .none)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(FinifyColor.Overflow.background)
        }
    }
}

/// 示意：Cover Flow——中間一張正面，兩側斜放，下方有淡淡的倒影
private struct CoverFlowPreview: View {
    let albums: [Album]
    private let side: CGFloat = 80

    var body: some View {
        ZStack {
            FinifyColor.Overflow.background
            RadialGradient(colors: [FinifyColor.accent.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: 150)
            ZStack {
                // 由外往內畫，中間那張疊在最上面
                ForEach([-2, 2, -1, 1, 0], id: \.self) { offset in
                    if let album = album(at: offset) { cover(album, offset: offset) }
                }
            }
            .offset(y: 10)
        }
    }

    private func album(at offset: Int) -> Album? {
        let index = offset + 2
        return albums.indices.contains(index) ? albums[index] : nil
    }

    private func cover(_ album: Album, offset: Int) -> some View {
        let distance = CGFloat(abs(offset))
        let x = offset == 0 ? 0 : CGFloat(offset.signum()) * (side * 0.8 + (distance - 1) * side * 0.42)
        return VStack(spacing: 2) {
            ArtworkView(artwork: album.artwork, cornerRadius: 3, elevation: .none)
                .frame(width: side, height: side)
            // 倒影
            ArtworkView(artwork: album.artwork, cornerRadius: 3, elevation: .none)
                .frame(width: side, height: side)
                .scaleEffect(x: 1, y: -1)
                .mask(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center))
                .frame(height: side * 0.4, alignment: .top)
                .clipped()
        }
        .rotation3DEffect(.degrees(Double(-offset.signum()) * 52), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .scaleEffect(offset == 0 ? 1 : 0.84)
        .brightness(-0.12 * Double(distance))
        .offset(x: x)
        .zIndex(-Double(distance))
    }
}
