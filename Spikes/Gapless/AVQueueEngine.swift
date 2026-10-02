import AVFoundation
import MediaToolbox

/// 方案 A：AVQueuePlayer。每個 item 掛 MTAudioProcessingTap 收集解碼後的 samples 與時間。
final class TapRecorder {
    private let lock = NSLock()
    private(set) var samples: [Float] = []
    /// 每個 buffer 的 (host time 秒, frames)
    private(set) var buffers: [(time: Double, frames: Int)] = []
    var sampleRate: Double = 44_100
    var armed = false

    func append(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        lock.lock(); defer { lock.unlock() }
        guard armed, frames > 0 else { return }
        let abl = UnsafeMutableAudioBufferListPointer(list)
        guard let data = abl[0].mData else { return }
        let ptr = data.assumingMemoryBound(to: Float.self)
        samples.append(contentsOf: UnsafeBufferPointer(start: ptr, count: frames))
        buffers.append((hostSeconds(), frames))
    }
}

func hostSeconds() -> Double {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return Double(mach_absolute_time()) * Double(info.numer) / Double(info.denom) / 1e9
}

private func makeTap(_ recorder: TapRecorder) -> MTAudioProcessingTap? {
    var callbacks = MTAudioProcessingTapCallbacks(
        version: kMTAudioProcessingTapCallbacksVersion_0,
        clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(recorder).toOpaque()),
        init: { _, clientInfo, storage in storage.pointee = clientInfo },
        finalize: { tap in
            Unmanaged<TapRecorder>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
        },
        prepare: { tap, _, format in
            let recorder = Unmanaged<TapRecorder>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
            recorder.sampleRate = format.pointee.mSampleRate
        },
        unprepare: nil,
        process: { tap, frames, _, bufferList, framesOut, flagsOut in
            guard MTAudioProcessingTapGetSourceAudio(tap, frames, bufferList, flagsOut, nil, framesOut) == noErr else { return }
            let recorder = Unmanaged<TapRecorder>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
            recorder.append(bufferList, frames: Int(framesOut.pointee))
        }
    )
    var tap: MTAudioProcessingTap?
    MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tap)
    return tap
}

private func makeItem(_ url: URL, recorder: TapRecorder) async throws -> AVPlayerItem {
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
        throw NSError(domain: "S2", code: 1, userInfo: [NSLocalizedDescriptionKey: "no audio track"])
    }
    let params = AVMutableAudioMixInputParameters(track: track)
    params.audioTapProcessor = makeTap(recorder)
    let mix = AVMutableAudioMix()
    mix.inputParameters = [params]
    let item = AVPlayerItem(asset: asset)
    item.audioMix = mix
    return item
}

/// 從 N 結尾前 `lead` 秒開始播，經過換曲，再錄 `tail` 秒。
@MainActor
func runAVQueue(_ t: Transition, lead: Double, tail: Double, withTap: Bool) async throws -> EngineResult {
    let recA = TapRecorder(), recB = TapRecorder()
    // MP3 透過 HTTP 時 AVFoundation 預設只估算長度與 seek 位置；要求精確時間才能正確計算
    let precise = [AVURLAssetPreferPreciseDurationAndTimingKey: true]
    let a = withTap ? try await makeItem(t.from.streamURL, recorder: recA) : AVPlayerItem(asset: AVURLAsset(url: t.from.streamURL, options: precise))
    let b = withTap ? try await makeItem(t.to.streamURL, recorder: recB) : AVPlayerItem(asset: AVURLAsset(url: t.to.streamURL, options: precise))
    let player = AVQueuePlayer(items: [a, b])
    player.automaticallyWaitsToMinimizeStalling = true
    // 喇叭不出聲；tap 為 PreEffects，仍收得到音量調整前的 samples（以 note 裡的 peak 驗證）
    player.volume = 0

    let deadline = Date().addingTimeInterval(15)
    while a.status != .readyToPlay {
        if a.status == .failed || Date() > deadline { throw a.error ?? NSError(domain: "S2", code: 2) }
        try await Task.sleep(for: .milliseconds(50))
    }
    await a.seek(to: CMTime(seconds: t.from.duration - lead, preferredTimescale: 600))
    recA.armed = true
    recB.armed = true
    player.play()
    // 時鐘法：每 5 ms 記錄 (牆上時間, 目前是哪首, 該首的 media time)，不依賴 tap
    var samplesClock: [(wall: Double, isB: Bool, t: Double)] = []
    let end = hostSeconds() + lead + tail
    while hostSeconds() < end {
        samplesClock.append((hostSeconds(), player.currentItem === b, player.currentTime().seconds))
        try await Task.sleep(for: .milliseconds(5))
    }
    player.pause()
    let durA = a.duration.seconds
    player.removeAllItems()

    let sr = recA.sampleRate
    let joined = recA.samples + recB.samples
    let junction = recA.samples.count
    var hostGapMs: Double? = nil
    if let lastA = recA.buffers.last, let firstB = recB.buffers.first {
        // B 第一個 buffer 的處理時間 −（A 最後一個 buffer 的處理時間 + 其長度）。tap 以 buffer 為單位被呼叫，誤差約一個 buffer。
        hostGapMs = (firstB.time - (lastA.time + Double(lastA.frames) / sr)) * 1000
    }
    let window = Int(0.75 * sr)
    let clockGap = clockGapMs(samplesClock, durationA: durA)
    return EngineResult(
        engine: withTap ? "AVQueuePlayer+tap" : "AVQueuePlayer",
        clockGapMs: clockGap,
        silenceAtJunctionMs: longestSilenceMs(joined, sampleRate: sr, from: junction - window, to: junction + window),
        hostGapMs: hostGapMs,
        reachedNext: !recB.samples.isEmpty,
        note: "durA \(durA), peak \(joined.map(abs).max() ?? 0), A frames \(recA.samples.count), B frames \(recB.samples.count), sr \(sr), buffers \(recA.buffers.first?.frames ?? 0)"
    )
}

/// 牆上時間比 media time 多走的部分 = 換曲時插入的停頓。
/// 取換曲前最後一個 A 樣本，與換曲後 B 播放 0.5 秒以上的第一個樣本比較，避開 B 起播瞬間的時間回報不穩。
func clockGapMs(_ s: [(wall: Double, isB: Bool, t: Double)], durationA: Double) -> Double? {
    guard let lastA = s.last(where: { !$0.isB }),
          let firstB = s.first(where: { $0.isB && $0.t >= 0.5 }) else { return nil }
    let wall = firstB.wall - lastA.wall
    let media = (durationA - lastA.t) + firstB.t
    return (wall - media) * 1000
}
