import SwiftUI

/// 文字分段切換：與右上角的模式切換同一種樣式——Liquid Glass 膠囊（macOS 26 以上；舊系統用色塊），選取的一段是主色。
/// 介面裡的分段切換一律用這個，不用系統 Picker 的 .segmented（樣式與其他控制項不一致）
struct GlassSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: LocalizedStringResource)]
    @Environment(\.overflowStyle) private var overflow

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.title)
                        .flioneFont(selected ? .bodyEmphasis : .body)
                        .lineLimit(1)
                        .padding(.horizontal, Spacing.s16)
                        .frame(height: 30)
                        .foregroundStyle(selected ? (overflow ? FlioneColor.Overflow.background : FlioneColor.onPrimary)
                                                  : (overflow ? FlioneColor.Overflow.muted : FlioneColor.muted))
                        .background(selected ? (overflow ? FlioneColor.Overflow.ink : FlioneColor.primary) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .modifier(TopBarSurface(overflow: overflow, shape: Capsule(), fallback: overflow ? FlioneColor.Overflow.control : FlioneColor.surface))
        .animation(Motion.micro, value: selection)
    }
}
