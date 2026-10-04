import SwiftUI

/// 短暫提示。4 秒後自動消失，也可以點一下關閉。
struct Toast: View {
    let message: String
    var icon: Reicon = .warning
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s12) {
            FlioneIcon(icon, size: .compact)
                .foregroundStyle(FlioneColor.warning)
            Text(message)
                .flioneFont(.body)
                .foregroundStyle(FlioneColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.s16)
        .padding(.vertical, Spacing.s12)
        .frame(maxWidth: 460)
        .flioneGlass(in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous), tint: FlioneColor.elevated.opacity(0.4), backing: FlioneColor.elevated.opacity(0.75),
                     fallback: FlioneColor.elevated)
        .flioneShadow(FlioneShadow.elevated)
        .onTapGesture(perform: onDismiss)
        .task {
            // 被新的提示取代時 task 會被取消，此時不能關掉新的提示
            guard (try? await Task.sleep(for: .seconds(4))) != nil else { return }
            onDismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .onAppear { NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue]) }
    }
}
