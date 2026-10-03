import SwiftUI

/// YouTube Music 登入後的狀態畫面（第一階段，docs/youtube/DESIGN.md）：
/// 連線中、連線失敗、已連線（音樂庫與播放在第二、三階段）。
struct YouTubeGateView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        VStack(spacing: Spacing.s24) {
            Image("LoginEmblem")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            content
                .frame(width: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FinifyColor.Ocean.abyss)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        switch app.youtube.state {
        case .checking, .signedOut:
            VStack(spacing: Spacing.s12) {
                ProgressView().controlSize(.small)
                Text("Connecting to YouTube Music…")
                    .finifyFont(.body).foregroundStyle(FinifyColor.muted)
            }
        case .connected(let name):
            message(title: "Connected to YouTube Music",
                    detail: "Signed in as \(name). Your library and playback are still being built on this branch.")
        case .failed(let reason):
            message(title: "Can't connect to YouTube Music", detail: "\(reason)") {
                FinifyButton(title: "Retry", kind: .primary) { Task { await app.youtube.check() } }
            }
        }
    }

    private func message<Actions: View>(title: LocalizedStringResource, detail: LocalizedStringResource,
                                        @ViewBuilder actions: () -> Actions = { EmptyView() }) -> some View {
        VStack(spacing: Spacing.s12) {
            Text(title).finifyFont(.title).foregroundStyle(FinifyColor.ink).multilineTextAlignment(.center)
            Text(detail).finifyFont(.body).foregroundStyle(FinifyColor.muted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.s8) {
                actions()
                FinifyButton(title: "Sign Out", kind: .secondary) { Task { await app.youtube.signOut() } }
            }
            .padding(.top, Spacing.s12)
        }
    }
}
