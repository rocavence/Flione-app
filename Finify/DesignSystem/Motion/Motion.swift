import SwiftUI

/// 動態 token。每個動畫都要有目的；Reduce Motion 開啟時呼叫端改用 `Motion.respecting`。
enum Motion {
    /// hover、press（120–180 ms）
    static let micro = Animation.easeOut(duration: 0.15)
    /// UI 轉場（180–280 ms）
    static let ui = Animation.easeInOut(duration: 0.24)
    /// Artwork 轉場（300–600 ms）
    static let artwork = Animation.spring(response: 0.45, dampingFraction: 0.86)
    /// Ambient 背景（2–8 s）
    static let ambient = Animation.easeInOut(duration: 3.0)
    /// 迷你播放器控制項淡入淡出
    static let controlsFade = Animation.easeInOut(duration: 0.6)

    /// Reduce Motion 時以短 crossfade 取代
    static func respecting(_ reduceMotion: Bool, _ animation: Animation) -> Animation {
        reduceMotion ? .linear(duration: 0.12) : animation
    }
}
