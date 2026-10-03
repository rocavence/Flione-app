import SwiftUI

/// 首次啟動：連線 Jellyfin。只需要 server 位址（可只填主機名稱）、帳號、密碼。
struct ConnectView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var server = AppEnvironment.lastServerAddress ?? ""
    @State private var user = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 進場：花翼幽幽浮現，再淡入文字與表單
    @State private var emblemShown = false
    @State private var contentShown = false
    @State private var breathing = false
    /// 這個分支以 YouTube Music 為主要登入方式；Jellyfin 表單點「改用 Jellyfin 伺服器」才展開
    @State private var showsJellyfin = false

    private enum Field { case server, user, password }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            emblem
                .padding(.bottom, Spacing.s24)
            VStack(spacing: Spacing.s12) {
                Text("FLIONE")
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(8)
                    .foregroundStyle(FinifyColor.ink)
                Text("Your music. Your server.")
                    .finifyFont(.title)
                    .foregroundStyle(FinifyColor.ink)
                Text(showsJellyfin ? "Connect to your Jellyfin server to bring your library in." : "Sign in with YouTube Music, or connect your own Jellyfin server.")
                    .finifyFont(.body)
                    .foregroundStyle(FinifyColor.muted)
            }
            .padding(.bottom, Spacing.s40)
            .opacity(contentShown ? 1 : 0)
            .offset(y: contentShown ? 0 : 6)

            Group {
            if showsJellyfin {
            VStack(spacing: Spacing.s12) {
                if let reason = app.signOutReason {
                    HStack(alignment: .top, spacing: Spacing.s8) {
                        FinifyIcon(.infoCircle, size: .compact)
                        Text(reason).finifyFont(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(FinifyColor.muted)
                    .padding(Spacing.s12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FinifyColor.surface, in: RoundedRectangle(cornerRadius: Radius.ui, style: .continuous))
                    .padding(.bottom, Spacing.s8)
                }
                field("Server", text: $server, prompt: "mediabox or 192.168.1.10:8096", field: .server)
                field("Username", text: $user, prompt: "", field: .user)
                field("Password", text: $password, prompt: "", field: .password, secure: true)

                if let errorMessage {
                    HStack(alignment: .top, spacing: Spacing.s8) {
                        FinifyIcon(.warning, size: .compact)
                        Text(errorMessage).finifyFont(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(FinifyColor.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                }

                FinifyButton(title: isConnecting ? "Connecting…" : "Connect", kind: .primary, isLoading: isConnecting, expands: true, action: connect)
                    .disabled(server.isEmpty || user.isEmpty)
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, Spacing.s8)
            }
            .frame(width: 320)
            .animation(Motion.ui, value: errorMessage)
            } else {
                youtubeOptions
            }
            }
            .opacity(contentShown ? 1 : 0)

            Spacer()
            Text("Flione talks only to your server. No account, no tracking.")
                .finifyFont(.caption)
                .foregroundStyle(FinifyColor.faint)
                .padding(.bottom, Spacing.s24)
                .opacity(contentShown ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 登入畫面固定深色：花翼是黑底發光的圖，深色底才能讓它從黑暗中浮出來；底色跟著配色
        .background(FinifyColor.Ocean.abyss)
        .environment(\.colorScheme, .dark)
        .onAppear {
            focus = server.isEmpty ? .server : .user
            reveal()
        }
    }

    /// YouTube Music：主要按鈕開 Google 登入視窗；Jellyfin 是次要選項
    private var youtubeOptions: some View {
        VStack(spacing: Spacing.s16) {
            FinifyButton(title: "Sign in to YouTube Music with Google", kind: .primary, expands: true) {
                GoogleSignIn.present { Task { await app.youtube.didSignIn() } }
            }
            .keyboardShortcut(.defaultAction)
            Text("Google's sign-in page opens in a separate window.")
                .finifyFont(.caption)
                .foregroundStyle(FinifyColor.muted)
                .multilineTextAlignment(.center)
            Button("Use a Jellyfin server instead") {
                withAnimation(Motion.ui) { showsJellyfin = true }
                focus = server.isEmpty ? .server : .user
            }
            .buttonStyle(.plain)
            .finifyFont(.body)
            .foregroundStyle(FinifyColor.accent)
            .padding(.top, Spacing.s8)
        }
        .frame(width: 320)
    }

    /// 花翼：圖檔的黑底已轉成透明（依亮度），任何底色上都只留下光；背後一層柔光緩慢呼吸
    private var emblem: some View {
        ZStack {
            Image("LoginEmblem")
                .resizable()
                .scaledToFit()
                .blur(radius: 40)
                .opacity(breathing ? 0.55 : 0.3)
                .scaleEffect(1.15)
            Image("LoginEmblem")
                .resizable()
                .scaledToFit()
        }
        .frame(width: 180, height: 180)
        .opacity(emblemShown ? 1 : 0)
        .blur(radius: emblemShown ? 0 : 24)
        .scaleEffect(emblemShown ? 1 : 0.94)
        .accessibilityHidden(true)
    }

    private func reveal() {
        guard !reduceMotion else {
            emblemShown = true
            contentShown = true
            return
        }
        withAnimation(.easeInOut(duration: 2.4).delay(0.3)) { emblemShown = true }
        withAnimation(.easeOut(duration: 0.9).delay(1.4)) { contentShown = true }
        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true).delay(2.7)) { breathing = true }
    }

    private func field(_ label: LocalizedStringResource, text: Binding<String>, prompt: LocalizedStringResource, field: Field, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            Text(label).finifyFont(.micro).textCase(.uppercase).foregroundStyle(FinifyColor.muted)
            Group {
                if secure {
                    SecureField("", text: text, prompt: Text(prompt))
                } else {
                    TextField("", text: text, prompt: Text(prompt))
                }
            }
            .textFieldStyle(.plain)
            .finifyFont(.body)
            .focused($focus, equals: field)
            .padding(.horizontal, Spacing.s12)
            .frame(height: 34)
            .background(FinifyColor.surface, in: RoundedRectangle(cornerRadius: Radius.ui, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.ui, style: .continuous)
                    .strokeBorder(focus == field ? FinifyColor.accent.opacity(0.7) : .clear, lineWidth: 1)
            }
            .onSubmit(connect)
        }
    }

    private func connect() {
        guard !server.isEmpty, !user.isEmpty, !isConnecting else { return }
        isConnecting = true
        errorMessage = nil
        Task {
            defer { isConnecting = false }
            do {
                let (url, info) = try await JellyfinClient.discover(server)
                let client = JellyfinClient(serverURL: url)
                let session = try await client.authenticate(user: user, password: password, serverName: info.serverName ?? url.host ?? "Jellyfin")
                try app.signIn(session)
            } catch JellyfinError.invalidCredentials {
                errorMessage = String(localized: "That username and password didn't work. Check them and try again.")
            } catch JellyfinError.unreachable {
                errorMessage = String(localized: "Can't find a music server at that address. Check the address, and that this Mac can reach it.")
            } catch {
                errorMessage = String(localized: "The server answered, but something went wrong. Try again in a moment.")
            }
        }
    }
}
