import SwiftUI

/// 區塊標題
struct SectionHeader: View {
    let title: LocalizedStringResource
    var subtitle: LocalizedStringResource?
    var action: (title: LocalizedStringResource, run: () -> Void)?
    /// 動作按鈕前的圖示（例如「重新推薦」的重新整理）
    var actionIcon: Reicon?

    var body: some View {
        // 置中對齊：右側動作按鈕與旁邊的箭頭按鈕同高，用基線對齊會比箭頭低
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).flioneFont(.heading).foregroundStyle(FlioneColor.ink)
                if let subtitle {
                    Text(subtitle).flioneFont(.caption).foregroundStyle(FlioneColor.muted)
                }
            }
            Spacer()
            if let action {
                SectionActionButton(title: action.title, icon: actionIcon, action: action.run)
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
            .fill(overflow ? FlioneColor.Overflow.control : FlioneColor.surface)
            .opacity(dim ? 0.55 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityHidden(true)
    }
}

/// 區塊標題右側的動作（例如「重新推薦」「顯示全部」）：與旁邊的左右箭頭（FlioneIconButton）同一套樣式，
/// 平常沒有框也沒有底，只有圖示與文字；hover 時出現同樣的圓角底色
/// 段落標題右側的動作（例如「重新推薦」）：macOS 原生的無邊框按鈕，與排序選單同一種樣式
private struct SectionActionButton: View {
    let title: LocalizedStringResource
    let icon: Reicon?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s4) {
                if let icon { FlioneIcon(icon, size: .compact).scaleEffect(0.85) }
                Text(title)
            }
            .flioneFont(.caption)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.tint)
        .hoverBezel()
    }
}

/// 無邊框按鈕與選單的 hover：與 macOS 工具列按鈕一樣，滑過時出現淡淡的圓角底
private struct HoverBezel: ViewModifier {
    @State private var hovering = false
    @Environment(\.overflowStyle) private var overflow

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Spacing.s8)
            .frame(height: 26)
            .background(hovering ? (overflow ? FlioneColor.Overflow.controlHover : FlioneColor.surface) : .clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onHover { hovering = $0 }
            .animation(Motion.micro, value: hovering)
    }
}

extension View {
    func hoverBezel() -> some View { modifier(HoverBezel()) }
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
            FlioneIcon(icon, size: .large)
                .foregroundStyle(overflow ? FlioneColor.Overflow.faint : FlioneColor.faint)
            VStack(spacing: Spacing.s8) {
                Text(title)
                    .flioneFont(.heading)
                    .foregroundStyle(overflow ? FlioneColor.Overflow.ink : FlioneColor.ink)
                Text(message)
                    .flioneFont(.body)
                    .foregroundStyle(overflow ? FlioneColor.Overflow.muted : FlioneColor.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            if primary != nil || secondary != nil {
                HStack(spacing: Spacing.s8) {
                    if let primary { FlioneButton(title: primary.title, kind: .primary, action: primary.run) }
                    if let secondary { FlioneButton(title: secondary.title, kind: .secondary, action: secondary.run) }
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
                Capsule().fill(overflow ? Color.white.opacity(0.18) : FlioneColor.hairline)
                Capsule()
                    // 播放進度一律用橘色；音量、大小這類控制在三種模式一致：平常是文字色，hover／拖曳時變藍
                    .fill(isPlayback ? FlioneColor.orange : (active ? FlioneColor.accent : (overflow ? FlioneColor.Overflow.ink : FlioneColor.ink)))
                    .frame(width: max(0, min(1, shown)) * geo.size.width)
                    .flioneGlow(isPlayback, radius: 5)
            }
            // 軌道 3pt，hover／拖曳時 1.5 倍；圓點放在 overlay，不參與排版
            .frame(height: active ? 4.5 : 3)
            .overlay(alignment: .leading) {
                if onSeek != nil, active || alwaysShowsKnob {
                    Circle()
                        .fill(overflow ? FlioneColor.Overflow.ink : FlioneColor.ink)
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
