import AVKit
import SwiftUI

/// 「播放到」：選擇從哪個裝置出聲（AirPlay）。一次只從一個裝置出聲。
/// Jellyfin 用系統的 AVRoutePickerView 接 AVQueuePlayer；YouTube Music 的聲音在網頁播放器裡，
/// 改叫出 WebKit 的 AirPlay 選單（與 Kaset 相同，ADR-0010）。
struct OutputPickerButton: View {
    @Environment(AppEnvironment.self) private var app
    @State private var anchor = ScreenAnchor()

    var body: some View {
        if app.session?.isYouTube == true {
            FinifyIconButton(icon: .screencast, label: "Play To", isActive: app.youtubePlayer.isWireless) {
                app.youtubePlayer.showAirPlayPicker(at: anchor.screenPoint)
            }
            .background(ScreenAnchorView(anchor: anchor))
            .disabled(!app.youtubePlayer.hasTrack)
            .help(Text("Play To"))
        } else {
            // 系統的選單按鈕本身透明、疊在 Flione 的圖示上，外觀與其他按鈕一致
            FinifyIcon(.screencast, size: .standard)
                .foregroundStyle(FinifyColor.muted)
                .frame(width: 32, height: 32)
                .overlay { RoutePicker(player: app.player.routingPlayer) }
                .help(Text("Play To"))
                .accessibilityLabel(Text("Play To"))
        }
    }
}

/// 系統的 AirPlay 裝置選單；按鈕的圖示設成透明，只留下可以點的範圍
private struct RoutePicker: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.isRoutePickerButtonBordered = false
        for state in [AVRoutePickerView.ButtonState.normal, .normalHighlighted, .active, .activeHighlighted] {
            view.setRoutePickerButtonColor(.clear, for: state)
        }
        view.player = player
        return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {
        view.player = player
    }
}

/// 記下按鈕在螢幕上的位置，讓 WebKit 的選單出現在按鈕旁邊
@MainActor
final class ScreenAnchor {
    fileprivate weak var view: NSView?

    var screenPoint: CGPoint? {
        guard let view, let window = view.window else { return nil }
        return window.convertPoint(toScreen: view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil))
    }
}

private struct ScreenAnchorView: NSViewRepresentable {
    let anchor: ScreenAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.setAccessibilityElement(false)
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { anchor.view = view }
}
