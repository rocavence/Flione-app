import SwiftUI

/// 心情電台（D50）：與 YouTube Music「心情與時刻」相同的 8 種心情。
/// Jellyfin 依曲風關鍵字從自己的音樂庫挑歌；YouTube Music 用該分類的官方歌單
enum Mood: String, CaseIterable, Identifiable, Sendable {
    case chill, focus, party, workout, feelGood, romance, sad, sleep

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .chill: "Chill"
        case .focus: "Focus"
        case .party: "Party"
        case .workout: "Workout"
        case .feelGood: "Feel Good"
        case .romance: "Romance"
        case .sad: "Sad"
        case .sleep: "Sleep"
        }
    }

    /// YouTube Music「Moods & moments」的分類名稱（以英文讀取心情頁時）
    var youtubeName: String {
        switch self {
        case .chill: "Chill"
        case .focus: "Focus"
        case .party: "Party"
        case .workout: "Workout"
        case .feelGood: "Feel good"
        case .romance: "Romance"
        case .sad: "Sad"
        case .sleep: "Sleep"
        }
    }

    /// Jellyfin：曲風名稱含有這些字（不分大小寫）就算符合
    var genreKeywords: [String] {
        switch self {
        case .chill: ["chill", "ambient", "downtempo", "lounge", "bossa", "lo-fi", "lofi", "trip hop", "acoustic"]
        case .focus: ["classical", "ambient", "instrumental", "piano", "post-rock", "soundtrack", "score", "minimal", "baroque"]
        case .party: ["dance", "house", "disco", "edm", "electro", "club", "funk", "pop"]
        case .workout: ["rock", "metal", "hip hop", "hip-hop", "rap", "drum", "punk", "electronic", "trance"]
        case .feelGood: ["pop", "funk", "soul", "reggae", "disco", "indie pop", "motown", "swing"]
        case .romance: ["r&b", "soul", "bossa", "ballad", "vocal", "jazz", "love"]
        case .sad: ["folk", "singer", "indie", "alternative", "ballad", "blues", "emo", "acoustic"]
        case .sleep: ["ambient", "new age", "classical", "piano", "meditation", "sleep", "chill"]
        }
    }

    /// 卡片右下角的裝飾圖示（SF Symbols；沒有符合曲風的封面時用）
    var symbol: String {
        switch self {
        case .chill: "leaf.fill"
        case .focus: "scope"
        case .party: "party.popper.fill"
        case .workout: "figure.run"
        case .feelGood: "sun.max.fill"
        case .romance: "heart.fill"
        case .sad: "cloud.rain.fill"
        case .sleep: "moon.stars.fill"
        }
    }

    /// 卡片的漸層（左上 → 右下），每種心情一組固定顏色
    var colors: [Color] {
        switch self {
        case .chill: [Color(hex: 0x3FC1C9), Color(hex: 0x1B4F72)]
        case .focus: [Color(hex: 0x6C7BFF), Color(hex: 0x22265E)]
        case .party: [Color(hex: 0xFF4FB1), Color(hex: 0x6A1B9A)]
        case .workout: [Color(hex: 0xFF7A2F), Color(hex: 0xB0182C)]
        case .feelGood: [Color(hex: 0xFFC93C), Color(hex: 0xE8562A)]
        case .romance: [Color(hex: 0xFF6F91), Color(hex: 0x8E2A4F)]
        case .sad: [Color(hex: 0x7C8DA6), Color(hex: 0x2C3446)]
        case .sleep: [Color(hex: 0x4B3F8F), Color(hex: 0x120F2E)]
        }
    }
}
