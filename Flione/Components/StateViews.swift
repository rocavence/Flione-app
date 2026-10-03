import SwiftUI

/// 區塊標題
struct SectionHeader: View {
    let title: LocalizedStringResource
    var subtitle: LocalizedStringResource?
    var action: (title: LocalizedStringResource, run: () -> Void)?

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
                Button(action: action.run) { Text(action.title) }
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
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    var icon: Reicon = .musicNote
    var primary: (title: LocalizedStringResource, run: () -> Void)?
    var secondary: (title: LocalizedStringResource, run: () -> Void)?
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
    /// 分段滑桿（例如封面大小 6 段）：拖曳時吸附到最近的一段
    var steps: Int?
    /// 圓點平常也顯示（分段滑桿）；預設只在 hover／拖曳時出現
    var alwaysShowsKnob = false
    /// 播放進度用 Bright Coral Orange；音量、大小這類控制用 Flione Blue
    var isPlayback = true
    var onSeek: ((Double) -> Void)?
    @Environment(\.overflowStyle) private var overflow
    @State private var hovering = false
    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { geo in
            let shown = dragValue ?? value
            let active = hovering || dragValue != nil
            // hover／拖曳時圓點放大到 160%（11 → 18）
            let knob: CGFloat = active ? 18 : 11
            ZStack(alignment: .leading) {
                Capsule().fill(overflow ? Color.white.opacity(0.18) : FinifyColor.hairline)
                Capsule()
                    // 播放進度一律用橘色；音量、大小這類控制在三種模式一致：平常是文字色，hover／拖曳時變藍
                    .fill(isPlayback ? FinifyColor.orange : (active ? FinifyColor.accent : (overflow ? FinifyColor.Overflow.ink : FinifyColor.ink)))
                    .frame(width: max(0, min(1, shown)) * geo.size.width)
                    .finifyGlow(isPlayback, radius: 5)
            }
            // 軌道 3pt，hover／拖曳時 1.5 倍；圓點放在 overlay，不參與排版
            .frame(height: active ? 4.5 : 3)
            .overlay(alignment: .leading) {
                if onSeek != nil, active || alwaysShowsKnob {
                    Circle()
                        .fill(overflow ? FinifyColor.Overflow.ink : FinifyColor.ink)
                        .frame(width: knob, height: knob)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .offset(x: max(0, min(1, shown)) * geo.size.width - knob / 2)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged {
                    var v = max(0, min(1, $0.location.x / geo.size.width))
                    if let steps, steps > 1 { v = (v * Double(steps - 1)).rounded() / Double(steps - 1) }
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
