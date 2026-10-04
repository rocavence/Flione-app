import SwiftUI

/// 探索：用自己的話描述想聽什麼，從音樂庫裡挑專輯並附上理由。全部在這台 Mac 上完成（D48）
struct DiscoverView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(StandardRouter.self) private var router
    @State private var request = ""
    @State private var state: ViewState = .idle
    @State private var task: Task<Void, Never>?
    @FocusState private var focused: Bool

    private enum ViewState: Equatable {
        case idle
        case working
        case results(request: String, picks: [DiscoveryPick])
        case failed(String)
    }

    private static let suggestions: [LocalizedStringResource] = [
        "Jazz for a rainy day",
        "Something calm to focus on work",
        "90s albums I haven't heard in a while",
        "Upbeat music for a weekend morning",
        "Late-night electronic",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s32) {
                VStack(alignment: .leading, spacing: Spacing.s8) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s12) {
                        Text("Discover").flioneFont(.display).foregroundStyle(FlioneColor.ink)
                        // 裝置上的模型較小，推薦與理由的品質會有起伏
                        Text(verbatim: "Beta")
                            .flioneFont(.micro)
                            .foregroundStyle(FlioneColor.accent)
                            .padding(.horizontal, Spacing.s8)
                            .padding(.vertical, 3)
                            .background(FlioneColor.accent.opacity(0.14), in: Capsule())
                    }
                    Text("Describe what you feel like hearing, and Flione picks albums from your own library. It all happens on this Mac.")
                        .flioneFont(.body).foregroundStyle(FlioneColor.muted)
                }
                if DiscoveryEngine.isAvailable {
                    prompt
                    content
                } else {
                    MessageState(title: "Discover needs Apple Intelligence.",
                                 message: "Use macOS 26 or later and turn on Apple Intelligence in System Settings. Discover runs entirely on this Mac.",
                                 icon: .starSparkle)
                }
            }
            .padding(Spacing.s32)
        }
        .onAppear {
            focused = true
            #if DEBUG
            if let demo = UserDefaults.standard.string(forKey: "FlioneDemoDiscover"), state == .idle {
                request = demo
                Task {
                    for _ in 0..<100 where app.library.albums.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
                    run(demo)
                }
            }
            #endif
        }
        .onDisappear { task?.cancel() }
    }

    private var prompt: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            HStack(spacing: Spacing.s12) {
                FlioneIcon(.starSparkle, size: .standard).foregroundStyle(FlioneColor.accent)
                TextField("", text: $request, prompt: Text("What do you feel like hearing?"))
                    .textFieldStyle(.plain)
                    .flioneFont(.subheading)
                    .focused($focused)
                    .onSubmit { run(request) }
                if state == .working {
                    ProgressView().controlSize(.small)
                } else {
                    FlioneButton(title: "Find", kind: .primary) { run(request) }
                        .disabled(request.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, Spacing.s16)
            .frame(height: 52)
            .background(FlioneColor.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .frame(maxWidth: 720)

            HStack(spacing: Spacing.s8) {
                ForEach(Self.suggestions.indices, id: \.self) { index in
                    let suggestion = Self.suggestions[index]
                    Button {
                        request = String(localized: suggestion)
                        run(request)
                    } label: {
                        Text(suggestion)
                            .flioneFont(.caption)
                            .foregroundStyle(FlioneColor.muted)
                            .padding(.horizontal, Spacing.s12)
                            .frame(height: 28)
                            .background(FlioneColor.surface.opacity(0.6), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(state == .working)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            EmptyView()
        case .working:
            Text("Picking from your library…").flioneFont(.body).foregroundStyle(FlioneColor.muted)
        case .failed(let message):
            MessageState(title: "Couldn't find anything.", message: LocalizedStringResource(stringLiteral: message), icon: .starSparkle)
        case .results(let asked, let picks):
            VStack(alignment: .leading, spacing: Spacing.s16) {
                HStack {
                    Text("For “\(asked)”").flioneFont(.heading).foregroundStyle(FlioneColor.ink)
                    Spacer()
                    FlioneButton(title: "Play All", icon: .play, kind: .secondary) { playAll(picks) }
                }
                VStack(spacing: Spacing.s4) {
                    ForEach(picks) { pick in DiscoverRow(pick: pick) { router.openAlbum(pick.album) } }
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
        }
    }

    private func run(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, state != .working else { return }
        task?.cancel()
        state = .working
        let library = app.library.albums
        let repository = app.repository
        task = Task {
            let recent = Set(((try? await repository?.recentlyPlayed(limit: 100)) ?? []).map(\.id))
            // 25 秒沒結果就放棄：裝置上的模型偶爾會卡在很長的輸出
            let watchdog = Task {
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled, state == .working else { return }
                task?.cancel()
                state = .failed(String(localized: "Apple Intelligence couldn't answer this time. Try again, or describe it another way."))
            }
            defer { watchdog.cancel() }
            do {
                let picks = try await DiscoveryEngine.discover(text, library: library, recentlyPlayedIDs: recent)
                guard !Task.isCancelled else { return }
                state = .results(request: text, picks: picks)
            } catch DiscoveryError.noResults {
                state = .failed(String(localized: "Nothing in your library fits that. Try describing it another way."))
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(String(localized: "Apple Intelligence couldn't answer this time. Try again, or describe it another way."))
            }
        }
    }

    /// 依推薦順序把每張專輯的曲目接起來播放
    private func playAll(_ picks: [DiscoveryPick]) {
        guard let repository = app.repository else { return }
        Task {
            var tracks: [Track] = []
            for pick in picks {
                tracks += (try? await repository.tracks(inAlbum: pick.album.id)) ?? []
            }
            if !tracks.isEmpty { app.player.play(tracks) }
        }
    }
}

private struct DiscoverRow: View {
    let pick: DiscoveryPick
    let onOpen: () -> Void
    @Environment(AppEnvironment.self) private var app
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s16) {
            ArtworkView(artwork: pick.album.artwork, elevation: .none)
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: Spacing.s4) {
                HStack(spacing: Spacing.s8) {
                    Text(pick.album.name).flioneFont(.subheading).foregroundStyle(FlioneColor.ink).lineLimit(1)
                    if !pick.recentlyPlayed {
                        Text("Not played in a while")
                            .flioneFont(.micro)
                            .foregroundStyle(FlioneColor.accent)
                            .padding(.horizontal, Spacing.s8)
                            .padding(.vertical, 2)
                            .background(FlioneColor.accent.opacity(0.14), in: Capsule())
                    }
                }
                Text([pick.album.artistName, pick.album.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                    .flioneFont(.caption).foregroundStyle(FlioneColor.muted).lineLimit(1)
                Text(pick.reason)
                    .flioneFont(.body).foregroundStyle(FlioneColor.ink.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            FlioneIconButton(icon: .play, label: "Play") { app.player.play(album: pick.album) }
        }
        .padding(Spacing.s12)
        .background(hovering ? FlioneColor.surface.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: Radius.ui, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
    }
}
