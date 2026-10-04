import SwiftUI

/// 首頁的心情電台（D50）：一排 8 張漸層卡，點了就開始播；讀取中的那張顯示轉圈
struct MoodShelf: View {
    @Environment(AppEnvironment.self) private var app
    @State private var loading: Mood?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            SectionHeader(title: "Mood Radio")
            // 固定 4 欄 × 2 列：8 種心情剛好排滿，不會剩一張孤零零在第二列
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.s12), count: 4), spacing: Spacing.s12) {
                ForEach(Mood.allCases) { mood in
                    MoodCard(mood: mood, loading: loading == mood, playing: app.player.radioName == String(localized: mood.title)) {
                        start(mood)
                    }
                }
            }
        }
    }

    private func start(_ mood: Mood) {
        guard loading == nil else { return }
        loading = mood
        Task {
            await app.player.startMoodRadio(mood)
            loading = nil
        }
    }
}

private struct MoodCard: View {
    let mood: Mood
    let loading: Bool
    let playing: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: mood.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                // 右上角的柔光，讓卡片有一點深度
                RadialGradient(colors: [.white.opacity(hovering ? 0.32 : 0.22), .clear], center: .topTrailing, startRadius: 0, endRadius: 120)
                HStack(alignment: .bottom) {
                    Text(mood.title)
                        .font(.system(size: 17, weight: .bold))
                        .tracking(-0.2)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: Spacing.s4)
                    if loading {
                        ProgressView().controlSize(.small).tint(.white)
                    } else if playing {
                        FinifyIcon(.radio, size: .compact).foregroundStyle(.white)
                    } else {
                        FinifyIcon(.play, weight: .filled, size: .compact)
                            .foregroundStyle(.white)
                            .opacity(hovering ? 1 : 0)
                    }
                }
                .padding(Spacing.s12)
            }
            .frame(height: 76)
            .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .strokeBorder(.white.opacity(playing ? 0.7 : 0.1), lineWidth: playing ? 2 : 1)
            }
            .scaleEffect(hovering ? 1.03 : 1)
            .shadow(color: mood.colors[0].opacity(hovering ? 0.35 : 0), radius: 14, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
        .accessibilityLabel(Text("\(mood.title) radio"))
    }
}
