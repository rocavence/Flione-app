import AVFoundation
import SwiftUI

// S2 Gapless spike
// 參數：-repo <repo 路徑>  -out <json>  [-only <transition label 前綴>]
// 讀取 <repo>/.secrets/jellyfin.env 與 session.env，逐一測試換曲，輸出結果後關閉。

struct Track {
    let id: String
    let name: String
    let container: String
    let duration: Double
    static var server = ""
    static var token = ""

    var streamURL: URL {
        URL(string: "\(Track.server)/Audio/\(id)/stream.\(container)?static=true&ApiKey=\(Track.token)")!
    }
}

struct Transition {
    let label: String
    let from: Track
    let to: Track
}

struct EngineResult: Codable {
    let engine: String
    let clockGapMs: Double?
    let silenceAtJunctionMs: Double
    let hostGapMs: Double?
    let reachedNext: Bool
    let note: String
}

private let plan: [Transition] = {
    let dsotm1 = Track(id: "5e272fb46db8b120c59ecb607517fc6d", name: "Speak to Me/Breathe", container: "mp3", duration: 237.6)
    let dsotm2 = Track(id: "988d352b2c0fa6629fc6df38801fc730", name: "On the Run", container: "m4a", duration: 215.1)
    let dsotm3 = Track(id: "5293b0afff7766b23ba68ff43511e2c5", name: "Time", container: "m4a", duration: 424.9)
    let dsotm6 = Track(id: "a6716dffdbdaf722e8aa3b59653017fa", name: "Us and Them", container: "m4a", duration: 470.3)
    let dsotm7 = Track(id: "8f7a355a11685c9027b474ce56e42b3e", name: "Any Colour You Like", container: "m4a", duration: 205.7)
    let dsotm8 = Track(id: "07ab580c16684d4f8295ba98cd3a63d4", name: "Brain Damage", container: "m4a", duration: 230.6)
    let dsotm9 = Track(id: "2429538b5911f41956e8980593ba2289", name: "Eclipse", container: "m4a", duration: 121.3)
    let kandi1 = Track(id: "dcb06f497873eceed687639fb367face", name: "Destination Calabria", container: "mp3", duration: 465.1)
    let kandi2 = Track(id: "920c97d27b7503307e47b1970cfb5c02", name: "Lollipop", container: "mp3", duration: 270.0)
    let kandi3 = Track(id: "9b69497a1bcf770c2f0cd70d2283c6a1", name: "The Creeps", container: "mp3", duration: 270.0)
    let berlin1 = Track(id: "7b1427d205c850355f38b0a3fa11c592", name: "Spiel mit mir", container: "mp3", duration: 369.0)
    let berlin2 = Track(id: "4454080ea9829825017d1e7b6f88cd55", name: "Herzeleid", container: "mp3", duration: 237.9)
    let berlin3 = Track(id: "2c37c27ef72be078da330f96c04e0c1e", name: "Bestrafe mich", container: "m4a", duration: 229.3)
    return [
        Transition(label: "DSOTM 1→2 (mp3→aac)", from: dsotm1, to: dsotm2),
        Transition(label: "DSOTM 2→3 (aac→aac)", from: dsotm2, to: dsotm3),
        Transition(label: "DSOTM 6→7 (aac→aac)", from: dsotm6, to: dsotm7),
        Transition(label: "DSOTM 8→9 (aac→aac)", from: dsotm8, to: dsotm9),
        Transition(label: "Disco Kandi 1→2 (mp3→mp3)", from: kandi1, to: kandi2),
        Transition(label: "Disco Kandi 2→3 (mp3→mp3)", from: kandi2, to: kandi3),
        Transition(label: "Live aus Berlin 1→2 (mp3→mp3)", from: berlin1, to: berlin2),
        Transition(label: "Live aus Berlin 2→3 (mp3→aac)", from: berlin2, to: berlin3),
    ]
}()

private func loadEnv(_ url: URL) -> [String: String] {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
    var env: [String: String] = [:]
    for line in text.split(separator: "\n") {
        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
        if parts.count == 2 { env[parts[0]] = parts[1] }
    }
    return env
}

/// 原始檔案在接縫處本來就有的靜音（N 結尾 + N+1 開頭），作為對照組。
private func groundTruth(_ t: Transition, cache: URL) async throws -> [String: Double] {
    func local(_ track: Track) async throws -> URL {
        let dest = cache.appendingPathComponent("\(track.id).\(track.container)")
        if !FileManager.default.fileExists(atPath: dest.path) {
            let (tmp, _) = try await URLSession.shared.download(from: track.streamURL)
            try FileManager.default.moveItem(at: tmp, to: dest)
        }
        return dest
    }
    let a = try decodeChannel0(try await local(t.from))
    let b = try decodeChannel0(try await local(t.to))
    return [
        "fromTrailingSilenceMs": trailingSilenceMs(a.samples, sampleRate: a.sampleRate),
        "toLeadingSilenceMs": leadingSilenceMs(b.samples, sampleRate: b.sampleRate),
        "fromDecodedSeconds": Double(a.samples.count) / a.sampleRate,
        "fromTaggedSeconds": t.from.duration,
    ]
}

@MainActor
private func runAll(repo: URL, out: URL) async {
    let env = loadEnv(repo.appendingPathComponent(".secrets/jellyfin.env"))
        .merging(loadEnv(repo.appendingPathComponent(".secrets/session.env"))) { $1 }
    Track.server = env["JELLYFIN_URL"] ?? ""
    Track.token = env["JELLYFIN_TOKEN"] ?? ""
    let cache = repo.appendingPathComponent(".cache/s2")
    try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

    var results: [[String: Any]] = []
    let only = UserDefaults.standard.object(forKey: "only") as? String
    let attempts = max(1, UserDefaults.standard.integer(forKey: "attempts"))
    for t in plan where only == nil || t.label.hasPrefix(only!) {
        var row: [String: Any] = ["transition": t.label]
        do { row["groundTruth"] = try await groundTruth(t, cache: cache) } catch { row["groundTruthError"] = "\(error)" }
        for attempt in 1...attempts {
            for withTap in [false, true] {
                let key = withTap ? "avqueueTap\(attempt)" : "avqueue\(attempt)"
                do {
                    let r = try await runAVQueue(t, lead: 3, tail: 3, withTap: withTap)
                    row[key] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(r))
                } catch { row[key + "Error"] = "\(error)" }
            }
            do {
                let r = try await StreamingRun().run(t, lead: 3, tail: 3)
                row["streaming\(attempt)"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(r))
            } catch { row["streaming\(attempt)Error"] = "\(error)" }
        }
        results.append(row)
        print("done:", t.label)
        let data = try! JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        try? data.write(to: out)
    }
    NSApp.terminate(nil)
}

@main
struct GaplessSpikeApp: App {
    var body: some Scene {
        WindowGroup {
            Text("S2 Gapless spike running…")
                .padding(40)
                .task {
                    let args = UserDefaults.standard
                    guard let repo = args.string(forKey: "repo"), let out = args.string(forKey: "out") else { return }
                    await runAll(repo: URL(fileURLWithPath: repo), out: URL(fileURLWithPath: out))
                }
        }
    }
}
