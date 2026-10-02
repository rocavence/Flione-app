import SwiftUI

/// 短暫提示。4 秒後自動消失，也可以點一下關閉。
struct Toast: View {
    let message: String
    var icon: Reicon = .warning
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s12) {
            FinifyIcon(icon, size: .compact)
                .foregroundStyle(FinifyColor.accent)
            Text(message)
                .finifyFont(.body)
                .foregroundStyle(FinifyColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.s16)
        .padding(.vertical, Spacing.s12)
        .frame(maxWidth: 460)
        .background(FinifyColor.elevated, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(FinifyColor.hairline, lineWidth: 1) }
        .finifyShadow(FinifyShadow.elevated)
        .onTapGesture(perform: onDismiss)
        .task {
            try? await Task.sleep(for: .seconds(4))
            onDismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .onAppear { NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue]) }
    }
}
