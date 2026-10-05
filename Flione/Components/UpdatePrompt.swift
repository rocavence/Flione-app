import AppKit
import SwiftUI

/// 右下角的新版提示（D53）：版本、更新內容的前幾點、下載（這台 Mac 對應的 dmg）、略過這個版本
struct UpdatePrompt: View {
    let release: UpdateChecker.Release
    let onSkip: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            HStack(alignment: .top, spacing: Spacing.s12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Flione \(release.version) is available").flioneFont(.subheading).foregroundStyle(FlioneColor.ink)
                    Text("You have \(UpdateChecker.currentVersion). Download it and drag it into Applications to replace this version.")
                        .flioneFont(.caption).foregroundStyle(FlioneColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
                .accessibilityLabel("Close")
            }
            if !release.notes.isEmpty {
                Text(release.notes)
                    .flioneFont(.caption)
                    .foregroundStyle(FlioneColor.ink.opacity(0.85))
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Spacing.s8) {
                FlioneButton(title: "Download", kind: .primary) {
                    NSWorkspace.shared.open(release.downloadURL ?? release.pageURL)
                    onClose()
                }
                Button("What's New") { NSWorkspace.shared.open(release.pageURL) }
                    .buttonStyle(.borderless)
                    .flioneFont(.caption)
                    .hoverBezel()
                Spacer(minLength: 0)
                Button("Skip This Version", action: onSkip)
                    .buttonStyle(.borderless)
                    .flioneFont(.caption)
                    .foregroundStyle(FlioneColor.muted)
                    .hoverBezel()
            }
        }
        .padding(Spacing.s16)
        .frame(width: 360)
        .flioneGlass(in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous), tint: FlioneColor.elevated.opacity(0.4),
                     backing: FlioneColor.elevated.opacity(0.85), fallback: FlioneColor.elevated)
        .flioneShadow(FlioneShadow.elevated)
        .accessibilityElement(children: .contain)
    }
}
