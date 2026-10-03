import AppKit

/// Force Touch 觸控板的觸覺回饋。只用在播放控制、切換與滑桿換段，不是每顆按鈕都有。
/// 對照表參考 Kaset（MIT）的 HapticService。
@MainActor
enum Haptics {
    enum Kind {
        /// 播放、暫停、上一首、下一首
        case playback
        /// 喜愛、隨機、重複這類開關
        case toggle
        /// 滑桿跳到下一段
        case step

        var pattern: NSHapticFeedbackManager.FeedbackPattern {
            switch self {
            case .playback: .generic
            case .toggle, .step: .alignment
            }
        }
    }

    static func perform(_ kind: Kind) {
        NSHapticFeedbackManager.defaultPerformer.perform(kind.pattern, performanceTime: .now)
    }
}
