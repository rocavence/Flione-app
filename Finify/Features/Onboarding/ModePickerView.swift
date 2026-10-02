import SwiftUI

/// 登入後選擇體驗：Standard 或 Overflow。兩者是平級的 App 入口。
struct ModePickerView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        @Bindable var app = app
        VStack(spacing: Spacing.s40) {
            VStack(spacing: Spacing.s8) {
                Text("Choose your experience")
                    .finifyFont(.title)
                    .foregroundStyle(FinifyColor.ink)
                Text("You can switch anytime with ⌘1 and ⌘2.")
                    .finifyFont(.body)
                    .foregroundStyle(FinifyColor.muted)
            }
            HStack(spacing: Spacing.s24) {
                ModeCard(mode: .standard, title: "Standard", subtitle: "Your library, organized.\nBrowse, search, and build a queue.") { app.mode = .standard }
                ModeCard(mode: .overflow, title: "Overflow", subtitle: "Your library as a wall of albums.\nImmersive, artwork first.") { app.mode = .overflow }
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
    let mode: AppMode
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
                    .frame(width: 320, height: 220)
                    .clipped()
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    Text(title).finifyFont(.heading).foregroundStyle(FinifyColor.ink)
                    Text(subtitle).finifyFont(.caption).foregroundStyle(FinifyColor.muted).fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.s20)
            }
            .frame(width: 320)
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
        case .overflow:
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
