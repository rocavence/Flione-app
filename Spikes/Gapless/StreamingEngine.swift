import AVFoundation
import AudioStreaming

/// tap 在 audio thread 寫入，main thread 讀取
final class SampleBox: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var armed = false
    private var startedNextAt: Int?

    func arm() { lock.withLock { armed = true } }
    func append(_ ptr: UnsafePointer<Float>, count: Int) {
        lock.withLock { if armed { samples.append(contentsOf: UnsafeBufferPointer(start: ptr, count: count)) } }
    }
    func markNext() { lock.withLock { if armed { startedNextAt = samples.count } } }
    var snapshot: ([Float], Int?) { lock.withLock { (samples, startedNextAt) } }
}

/// 方案 B：AudioStreaming（AVAudioEngine）。
/// 在 main mixer 之前插入一個 passthrough node 錄下連續輸出；main mixer 音量設 0，所以喇叭沒有聲音。
@MainActor
final class StreamingRun: AudioPlayerDelegate {
    private let player = AudioPlayer()
    private let box = SampleBox()
    private var error: String?
    private var nextID = ""
    private var events: [String] = []
    private var t0 = hostSeconds()

    private func log(_ s: String) { events.append(String(format: "%.2f ", hostSeconds() - t0) + s) }

    /// AudioStreaming 1.4.5：seek 前就 queue 的項目在目前曲目結束後不會播放，所以 seek 完才 queue
    var queueAfterSeek = true

    func run(_ t: Transition, lead: Double, tail: Double) async throws -> EngineResult {
        nextID = t.to.streamURL.absoluteString
        player.delegate = self
        let box = box
        let tapNode = AVAudioMixerNode()
        player.attach(node: tapNode)
        player.volume = 0
        tapNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            if let ch0 = buffer.floatChannelData?[0] { box.append(ch0, count: Int(buffer.frameLength)) }
        }
        t0 = hostSeconds()
        player.play(url: t.from.streamURL)
        if !queueAfterSeek { player.queue(url: t.to.streamURL) }
        log("play")

        let deadline = Date().addingTimeInterval(15)
        while player.state != .playing {
            if let error { throw NSError(domain: "S2", code: 3, userInfo: [NSLocalizedDescriptionKey: error]) }
            if Date() > deadline { throw NSError(domain: "S2", code: 4, userInfo: [NSLocalizedDescriptionKey: "timeout waiting to play, state \(player.state)"]) }
            try await Task.sleep(for: .milliseconds(50))
        }
        log("playing, duration \(player.duration)")
        player.seek(to: t.from.duration - lead - 0.5)
        log("seek")
        try await Task.sleep(for: .milliseconds(500))
        if queueAfterSeek { player.queue(url: t.to.streamURL); log("queue after seek") }
        box.arm()
        let end = hostSeconds() + lead + tail
        var lastLog = 0.0
        while hostSeconds() < end {
            if hostSeconds() - lastLog > 0.5 { lastLog = hostSeconds(); log("progress \(String(format: "%.2f", player.progress)) state \(player.state)") }
            try await Task.sleep(for: .milliseconds(20))
        }
        player.stop()
        tapNode.removeTap(onBus: 0)

        let sr = tapNode.outputFormat(forBus: 0).sampleRate
        let (x, junction) = box.snapshot
        let window = Int(1.0 * sr)
        let center = junction ?? Int(lead * sr)
        return EngineResult(
            engine: "AudioStreaming",
            clockGapMs: nil,
            silenceAtJunctionMs: longestSilenceMs(x, sampleRate: sr, from: center - window, to: center + window),
            hostGapMs: nil,
            reachedNext: junction != nil,
            note: "peak \(x.map(abs).max() ?? 0), frames \(x.count), sr \(sr), junction \(junction.map(String.init) ?? "nil")\(error.map { ", error \($0)" } ?? "") | " + events.joined(separator: " ; ")
        )
    }

    nonisolated func audioPlayerDidStartPlaying(player: AudioPlayer, with entryId: AudioEntryId) {
        MainActor.assumeIsolated {
            log("didStart \(entryId.id.suffix(60))")
            guard entryId.id == nextID else { return }
            box.markNext()
        }
    }

    nonisolated func audioPlayerUnexpectedError(player: AudioPlayer, error: AudioPlayerError) {
        MainActor.assumeIsolated { self.error = "\(error)"; log("error \(error)") }
    }

    nonisolated func audioPlayerDidFinishBuffering(player: AudioPlayer, with entryId: AudioEntryId) {
        MainActor.assumeIsolated { log("didFinishBuffering \(entryId.id.suffix(30))") }
    }
    nonisolated func audioPlayerStateChanged(player: AudioPlayer, with newState: AudioPlayerState, previous: AudioPlayerState) {
        MainActor.assumeIsolated { log("state \(previous)→\(newState)") }
    }
    nonisolated func audioPlayerDidFinishPlaying(player: AudioPlayer, entryId: AudioEntryId, stopReason: AudioPlayerStopReason, progress: Double, duration: Double) {
        MainActor.assumeIsolated { log("didFinish \(stopReason) progress \(progress) duration \(duration)") }
    }
    nonisolated func audioPlayerDidCancel(player: AudioPlayer, queuedItems: [AudioEntryId]) {}
    nonisolated func audioPlayerDidReadMetadata(player: AudioPlayer, metadata: [String: String]) {}
}
