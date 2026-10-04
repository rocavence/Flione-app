import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 一張推薦的專輯
struct DiscoveryPick: Identifiable, Hashable {
    let album: Album
    let reason: String
    /// 最近播過（不在「很久沒聽」之列）
    let recentlyPlayed: Bool
    var id: String { album.id }
}

enum DiscoveryError: Error {
    case unavailable
    case noResults
    case failed
}

/// AI 探索：用 Apple 裝置上的模型（Foundation Models），只從使用者自己的音樂庫推薦，資料不離開這台 Mac（D48）。
/// 模型一次能讀的內容有限，整個音樂庫放不進去，所以分兩步：
/// 1. 把需求轉成條件（曲風只能從音樂庫有的曲風挑、年代、藝人）
/// 2. 依條件篩出最多 40 張候選（很久沒聽的優先），再讓模型挑最多 8 張並寫一句理由
enum DiscoveryEngine {
    static let maxCandidates = 30
    static let maxPicks = 8

    /// 這台 Mac 能不能用（macOS 26 以上且開啟 Apple Intelligence）
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static func discover(_ request: String, library: [Album], recentlyPlayedIDs: Set<String>) async throws -> [DiscoveryPick] {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            guard isAvailable else { throw DiscoveryError.unavailable }
            return try await run(request, library: library, recent: recentlyPlayedIDs)
        }
        #endif
        throw DiscoveryError.unavailable
    }

    // MARK: - 篩選候選（不用模型）

    struct Criteria {
        var genres: [String] = []
        var decades: [Int] = []
        var artists: [String] = []
    }

    /// 依條件給分；沒有任何條件符合時退回整個音樂庫。很久沒聽的排前面，同分隨機，每次結果不同
    static func candidates(from library: [Album], criteria: Criteria, recent: Set<String>) -> [Album] {
        // 模型越前面列的曲風越相關：第一個 5 分，往後遞減（避免最常見的 Pop 佔滿候選）
        let genreWeight = Dictionary(criteria.genres.enumerated().map { ($1.lowercased(), max(1, 5 - $0)) }) { first, _ in first }
        let artists = criteria.artists.map { $0.lowercased() }
        func score(_ album: Album) -> Int {
            var value = 0
            if let albumGenres = album.genres {
                value += albumGenres.compactMap { genreWeight[$0.lowercased()] }.max() ?? 0
            }
            if let year = album.year, criteria.decades.contains(where: { year >= $0 && year < $0 + 10 }) { value += 2 }
            let artist = album.artistName.lowercased()
            if artists.contains(where: { artist.contains($0) || $0.contains(artist) }) { value += 4 }
            return value
        }
        let hasCriteria = !genreWeight.isEmpty || !criteria.decades.isEmpty || !artists.isEmpty
        let scored = library.map { (album: $0, score: score($0), recent: recent.contains($0.id), tiebreak: Int.random(in: 0..<1_000_000)) }
        let matched = hasCriteria ? scored.filter { $0.score > 0 } : scored
        let pool = matched.isEmpty ? scored : matched
        return pool.sorted {
            if $0.recent != $1.recent { return !$0.recent }
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.tiebreak < $1.tiebreak
        }
        .prefix(maxCandidates)
        .map(\.album)
    }

    /// 音樂庫最常見的曲風，給模型挑選（最多 80 個，控制提示長度）
    static func genreVocabulary(_ library: [Album]) -> [String] {
        var counts: [String: Int] = [:]
        for genre in library.flatMap({ $0.genres ?? [] }) { counts[genre, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.prefix(80).map(\.key)
    }
}

extension DiscoveryEngine {
    /// 模型偶爾把 JSON 符號混進句子（例如 `」}, {`、`}]}```）：遇到括號就截斷，再清掉句尾的符號
    static func cleaned(_ reason: String) -> String {
        let cut = reason.firstIndex { "{}[]".contains($0) }.map { String(reason[..<$0]) } ?? reason
        return cut.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "`\"',，、」")))
    }

    /// DEBUG：-FinifyDiscoverLog <檔案> 記錄每一步，查哪裡慢或失敗
    static func debugNote(_ line: String) {
        #if DEBUG
        guard let path = UserDefaults.standard.string(forKey: "FinifyDiscoverLog") else { return }
        if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        handle.seekToEndOfFile()
        handle.write(Data("\(Date().formatted(.dateTime.hour().minute().second())) \(line)\n".utf8))
        try? handle.close()
        #endif
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
struct DiscoveryIntent {
    @Guide(description: "Only genres the request clearly asks for, using the exact spelling from the list. Empty if the request names no genre or style.", .maximumCount(5))
    let genres: [String]
    @Guide(description: "Decades the request asks for, as the first year, e.g. 1990 for the 90s. Empty if none.")
    let decades: [Int]
    @Guide(description: "Artist names the request mentions or clearly implies. Empty if none.", .maximumCount(5))
    let artists: [String]
}

@available(macOS 26, *)
@Generable
struct DiscoveryChoice {
    @Guide(description: "The number of the album in the list.")
    let number: Int
    @Guide(description: "One short, specific sentence about this album or artist and why it fits.")
    let reason: String
}

@available(macOS 26, *)
@Generable
struct DiscoveryChoices {
    // 上限要寫在 Guide 裡：只寫在描述中，模型會一直產生下去直到超過 8,192 token 的上限
    @Guide(description: "The albums from the list that best fit the request, best first.", .maximumCount(8))
    let choices: [DiscoveryChoice]
}

@available(macOS 26, *)
extension DiscoveryEngine {
    fileprivate static func run(_ request: String, library: [Album], recent: Set<String>) async throws -> [DiscoveryPick] {
        // 1. 需求 → 條件
        debugNote("start: \(library.count) albums, \(recent.count) recent")
        let vocabulary = genreVocabulary(library)
        let intentSession = LanguageModelSession(instructions: """
            You turn a music listening request into search criteria for the user's own music library. \
            Only choose genres from this list: \(vocabulary.joined(separator: ", ")).
            """)
        let intent: DiscoveryIntent
        do {
            intent = try await intentSession.respond(to: request, generating: DiscoveryIntent.self,
                                                     options: GenerationOptions(maximumResponseTokens: 300)).content
        } catch {
            debugNote("intent error: \(error)")
            throw error
        }
        debugNote("intent: genres=\(intent.genres) decades=\(intent.decades) artists=\(intent.artists)")
        // 模型給的藝人要在音樂庫找得到才採用（避免把「90 年代」之類當成藝人）
        let libraryArtists = Set(library.map { $0.artistName.lowercased() })
        let artists = intent.artists.filter { name in libraryArtists.contains { $0.contains(name.lowercased()) } }
        let pool = candidates(from: library, criteria: Criteria(genres: intent.genres, decades: intent.decades, artists: artists), recent: recent)
        guard !pool.isEmpty else { throw DiscoveryError.noResults }

        // 2. 候選 → 挑選＋理由
        let list = pool.enumerated().map { index, album in
            var line = "\(index + 1). \(album.name) — \(album.artistName)"
            let details = [album.year.map(String.init), album.genres?.prefix(2).joined(separator: "/")].compactMap { $0 }.filter { !$0.isEmpty }
            if !details.isEmpty { line += " (\(details.joined(separator: ", ")))" }
            if !recent.contains(album.id) { line += " [not played recently]" }
            return line
        }.joined(separator: "\n")
        let language = AppLanguage.effective.modelInstruction
        let pickSession = LanguageModelSession(instructions: """
            You recommend albums from the user's own music library. Choose only from the numbered list. \
            Prefer albums marked [not played recently] when they fit equally well. Write each reason in \(language). \
            Each reason is one short sentence that names something specific about that album or artist, such as the era, \
            tempo or mood, and says how it fits the request. Mention an instrument only if you are certain the artist plays it; \
            otherwise describe the era or mood instead. Do not start with "This album" or 「這張專輯」, \
            do not repeat the album title, and make every reason different.
            """)
        debugNote("candidates: \(pool.count)\n\(list)")
        let choices: [DiscoveryChoice]
        do {
            // 字串沒有長度上限，模型偶爾會在某一句理由停不下來；限制回應長度，超過就失敗而不是一直生成
            choices = try await pickSession.respond(to: "Request: \(request)\n\nAlbums:\n\(list)", generating: DiscoveryChoices.self,
                                                    options: GenerationOptions(maximumResponseTokens: 700)).content.choices
        } catch {
            debugNote("pick error: \(error)")
            throw error
        }
        debugNote("choices: \(choices.map { "\($0.number) \(pool.indices.contains($0.number - 1) ? pool[$0.number - 1].name : "?")：\(cleaned($0.reason))" })")
        var seen = Set<String>()
        let picks = choices.compactMap { choice -> DiscoveryPick? in
            guard pool.indices.contains(choice.number - 1) else { return nil }
            let album = pool[choice.number - 1]
            guard seen.insert(album.id).inserted else { return nil }
            return DiscoveryPick(album: album, reason: cleaned(choice.reason), recentlyPlayed: recent.contains(album.id))
        }
        guard !picks.isEmpty else { throw DiscoveryError.noResults }
        return Array(picks.prefix(maxPicks))
    }
}
#endif
