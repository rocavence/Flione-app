import SwiftUI

/// 首次啟動：連線 Jellyfin。只需要 server 位址（可只填主機名稱）、帳號、密碼。
struct ConnectView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var server = ""
    @State private var user = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private enum Field { case server, user, password }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: Spacing.s12) {
                Text("FINIFY")
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(8)
                    .foregroundStyle(FinifyColor.ink)
                Text("Your music. Your server.")
                    .finifyFont(.title)
                    .foregroundStyle(FinifyColor.ink)
                Text("Connect to your Jellyfin server to bring your library in.")
                    .finifyFont(.body)
                    .foregroundStyle(FinifyColor.muted)
            }
            .padding(.bottom, Spacing.s40)

            VStack(spacing: Spacing.s12) {
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

            Spacer()
            Text("Finify talks only to your server. No account, no tracking.")
                .finifyFont(.caption)
                .foregroundStyle(FinifyColor.faint)
                .padding(.bottom, Spacing.s24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FinifyColor.paper)
        .onAppear { focus = .server }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String, field: Field, secure: Bool = false) -> some View {
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
                errorMessage = "That username and password didn't work. Check them and try again."
            } catch JellyfinError.unreachable {
                errorMessage = "Can't find a music server at that address. Check the address, and that this Mac can reach it."
            } catch {
                errorMessage = "The server answered, but something went wrong. Try again in a moment."
            }
        }
    }
}
