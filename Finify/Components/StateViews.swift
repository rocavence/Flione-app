import SwiftUI

/// 區塊標題
struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var action: (title: String, run: () -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).finifyFont(.heading).foregroundStyle(FinifyColor.ink)
                if let subtitle {
                    Text(subtitle).finifyFont(.caption).foregroundStyle(FinifyColor.muted)
                }
            }
            Spacer()
            if let action {
                Button(action.title, action: action.run)
                    .buttonStyle(.plain)
                    .finifyFont(.caption)
                    .foregroundStyle(FinifyColor.muted)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// 載入中的骨架。Reduce Motion 時不閃爍。
struct SkeletonBlock: View {
    var cornerRadius: CGFloat = Radius.small
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.overflowStyle) private var overflow
    @State private var dim = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(overflow ? FinifyColor.Overflow.control : FinifyColor.surface)
            .opacity(dim ? 0.55 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityHidden(true)
    }
}

/// 空狀態與錯誤狀態：說明發生什麼事，並給下一步。
struct MessageState: View {
    let title: String
    let message: String
    var icon: Reicon = .musicNote
    var primary: (title: String, run: () -> Void)?
    var secondary: (title: String, run: () -> Void)?
    @Environment(\.overflowStyle) private var overflow

    var body: some View {
        VStack(spacing: Spacing.s16) {
            FinifyIcon(icon, size: .large)
                .foregroundStyle(overflow ? FinifyColor.Overflow.faint : FinifyColor.faint)
            VStack(spacing: Spacing.s8) {
                Text(title)
                    .finifyFont(.heading)
                    .foregroundStyle(overflow ? FinifyColor.Overflow.ink : FinifyColor.ink)
                Text(message)
                    .finifyFont(.body)
                    .foregroundStyle(overflow ? FinifyColor.Overflow.muted : FinifyColor.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            if primary != nil || secondary != nil {
                HStack(spacing: Spacing.s8) {
                    if let primary { FinifyButton(title: primary.title, kind: .primary, action: primary.run) }
                    if let secondary { FinifyButton(title: secondary.title, kind: .secondary, action: secondary.run) }
                }
                .padding(.top, Spacing.s8)
            }
        }
        .padding(Spacing.s40)
        .frame(maxWidth: .infinity)
    }
}

/// 可拖曳的進度條。hover 時加粗並顯示把手。
struct ProgressBar: View {
    let value: Double
    /// 拖曳時持續回報（音量）；否則放開時才回報（播放進度）
    var continuous = false
    var onSeek: ((Double) -> Void)?
    @Environment(\.overflowStyle) private var overflow
    @State private var hovering = false
    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { geo in
            let shown = dragValue ?? value
            let height: CGFloat = hovering || dragValue != nil ? 5 : 3
            ZStack(alignment: .leading) {
                Capsule().fill(overflow ? Color.white.opacity(0.18) : FinifyColor.hairline)
                Capsule()
                    .fill(hovering || dragValue != nil ? FinifyColor.accent : (overflow ? FinifyColor.Overflow.ink : FinifyColor.ink))
                    .frame(width: max(0, min(1, shown)) * geo.size.width)
                if onSeek != nil, hovering || dragValue != nil {
                    Circle()
                        .fill(overflow ? FinifyColor.Overflow.ink : FinifyColor.ink)
                        .frame(width: 11, height: 11)
                        .offset(x: max(0, min(1, shown)) * geo.size.width - 5.5)
                }
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged {
                    let v = max(0, min(1, $0.location.x / geo.size.width))
                    dragValue = v
                    if continuous { onSeek?(v) }
                }
                .onEnded { _ in
                    if let dragValue { onSeek?(dragValue) }
                    dragValue = nil
                })
            .onHover { hovering = $0 }
            .animation(Motion.micro, value: hovering)
        }
        .frame(height: 14)
        // 對 VoiceOver 呈現為標準滑桿，可用上下鍵調整
        .accessibilityRepresentation {
            Slider(value: Binding(get: { value }, set: { onSeek?($0) }), in: 0...1)
                .accessibilityLabel("Playback position")
                .accessibilityValue("\(Int(value * 100)) percent")
        }
    }
}
