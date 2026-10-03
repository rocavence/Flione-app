import SwiftUI

/// YouTube Music 登入後、進入 Flione 前的狀態畫面（docs/youtube/DESIGN.md）：連線中、連線失敗。
/// 連線成功後 AppEnvironment 啟用 YouTube Music 的連線，畫面就是原本的 Modern／Infinity／Cover Flow。
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
        case .connected:
            EmptyView()
        case .failed(let reason):
            message(title: "Can't connect to YouTube Music", detail: "\(reason)") {
                FinifyButton(title: "Retry", kind: .primary) { Task { await app.signInYouTube() } }
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
