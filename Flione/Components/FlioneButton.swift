import SwiftUI

/// 文字按鈕。狀態：default、hover、pressed、focused（系統 focus ring）、disabled、loading。
struct FlioneButton: View {
    enum Kind {
        /// 主要行動（Play）
        case primary
        /// 次要行動（Shuffle）
        case secondary
        /// 不搶眼的行動
        case ghost
    }

    let title: LocalizedStringResource
    var icon: Reicon?
    var kind: Kind = .secondary
    var isLoading = false
    /// 填滿可用寬度（表單主按鈕）
    var expands = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s8) {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else if let icon {
                    FlioneIcon(icon, weight: kind == .primary ? .filled : .outline, size: .compact)
                }
                Text(title).flioneFont(.bodyEmphasis)
            }
            .frame(maxWidth: expands ? .infinity : nil)
        }
        .buttonStyle(FlioneButtonStyle(kind: kind))
        .disabled(isLoading)
    }
}

struct FlioneButtonStyle: ButtonStyle {
    let kind: FlioneButton.Kind

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, kind: kind)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        let kind: FlioneButton.Kind
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.overflowStyle) private var overflow
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(foreground)
                .padding(.horizontal, Spacing.s16)
                .frame(height: 32)
                .background(background, in: RoundedRectangle(cornerRadius: Radius.ui, style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .animation(Motion.micro, value: hovering)
                .animation(Motion.micro, value: configuration.isPressed)
                .onHover { hovering = $0 }
                .contentShape(Rectangle())
        }

        private var foreground: Color {
            switch kind {
            case .primary: overflow ? FlioneColor.Overflow.background : FlioneColor.onPrimary
            case .secondary, .ghost: overflow ? FlioneColor.Overflow.ink : FlioneColor.ink
            }
        }

        private var background: Color {
            switch kind {
            case .primary:
                let base = overflow ? FlioneColor.Overflow.ink : FlioneColor.primary
                return hovering ? base.opacity(0.88) : base
            case .secondary:
                if overflow { return hovering ? FlioneColor.Overflow.controlHover : FlioneColor.Overflow.control }
                return hovering ? FlioneColor.hairline : FlioneColor.surface
            case .ghost:
                guard hovering else { return .clear }
                return overflow ? FlioneColor.Overflow.control : FlioneColor.surface
            }
        }
    }
}

/// 只有 icon 的按鈕。`isActive` 時改用 Filled + `activeColor`（預設 Flione Blue；shuffle、repeat 用橘色）。
struct FlioneIconButton: View {
    let icon: Reicon
    let label: LocalizedStringResource
    var size: FlioneIcon.Size = .standard
    var isActive = false
    var activeColor: Color = FlioneColor.accent
    /// 主要播放按鈕：實心圓底
    var prominent = false
    let action: () -> Void

    @Environment(\.overflowStyle) private var overflow
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            FlioneIcon(icon, weight: isActive || prominent ? .filled : .outline, size: size)
                .foregroundStyle(foreground)
                .frame(width: size.rawValue + (prominent ? 20 : 12), height: size.rawValue + (prominent ? 20 : 12))
                .background(background, in: prominent ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: Radius.ui, style: .continuous)))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }

    private var foreground: Color {
        if prominent { return overflow ? FlioneColor.Overflow.background : FlioneColor.onPrimary }
        if isActive { return activeColor }
        let base = overflow ? FlioneColor.Overflow.ink : FlioneColor.ink
        return hovering ? base : base.opacity(0.72)
    }

    private var background: Color {
        if prominent {
            let base = overflow ? FlioneColor.Overflow.ink : FlioneColor.primary
            return hovering ? base.opacity(0.88) : base
        }
        guard hovering else { return .clear }
        return overflow ? FlioneColor.Overflow.control : FlioneColor.surface
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Motion.micro, value: configuration.isPressed)
    }
}

// MARK: - Overflow 環境

private struct OverflowStyleKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Overflow mode 永遠是深色、沉浸式；元件依此切換配色
    var overflowStyle: Bool {
        get { self[OverflowStyleKey.self] }
        set { self[OverflowStyleKey.self] = newValue }
    }
}
