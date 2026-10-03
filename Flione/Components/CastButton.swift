import SwiftUI

/// 「投放」：列出區域網路上的 Chromecast，選了就從那台出聲（一次只從一個裝置出聲，D43）。
/// YouTube Music 不支援：音訊在網頁播放器裡，沒有網址可以交給裝置
struct CastButton: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let youtube = app.session?.isYouTube == true
        // 不能用時（YouTube Music、還沒找到裝置）停用，外觀與其他停用的按鈕一致
        let unavailable = app.cast.activeDevice == nil && (youtube || app.cast.devices.isEmpty)
        Menu {
            if youtube {
                Text("Casting works with Jellyfin only")
            } else if app.cast.devices.isEmpty {
                Text("Looking for cast devices…")
            } else {
                ForEach(app.cast.devices) { device in
                    Button {
                        app.cast.cast(to: device, player: app.player)
                    } label: {
                        if app.cast.activeDevice?.id == device.id {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(verbatim: device.name)
                        }
                    }
                }
            }
            if app.cast.activeDevice != nil {
                Divider()
                Button("Stop Casting") { app.cast.stop(player: app.player) }
            }
        } label: {
            FinifyIcon(.tv, weight: app.cast.activeDevice == nil ? .outline : .filled, size: .standard)
                .foregroundStyle(app.cast.activeDevice == nil ? FinifyColor.muted : FinifyColor.accent)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        // borderlessButton 會把圖示畫成系統預設的黑色；button＋plain 才照 Flione 的顏色畫
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(unavailable)
        .opacity(unavailable ? 0.35 : 1)
        .help(Text(youtube ? "Casting works with Jellyfin only" : app.cast.activeDevice.map { "Casting to \($0.name)" } ?? (app.cast.devices.isEmpty ? "Looking for cast devices…" : "Cast")))
        .accessibilityLabel(Text("Cast"))
        .onAppear { app.cast.startDiscovery() }
    }
}
