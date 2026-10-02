import AVFoundation

/// 振幅低於此值視為靜音（約 -70 dBFS）。編碼器 padding 產生的是完全的 0，門檻只是容忍極小雜訊。
let silenceThreshold: Float = 0.0003

/// 在 [from, to) 範圍內找最長的連續靜音，回傳毫秒。
func longestSilenceMs(_ x: [Float], sampleRate: Double, from: Int, to: Int) -> Double {
    let lo = max(0, from), hi = min(x.count, to)
    guard lo < hi else { return 0 }
    var longest = 0, run = 0
    for i in lo..<hi {
        if abs(x[i]) < silenceThreshold { run += 1; longest = max(longest, run) } else { run = 0 }
    }
    return Double(longest) / sampleRate * 1000
}

func leadingSilenceMs(_ x: [Float], sampleRate: Double) -> Double {
    let n = x.firstIndex { abs($0) >= silenceThreshold } ?? x.count
    return Double(n) / sampleRate * 1000
}

func trailingSilenceMs(_ x: [Float], sampleRate: Double) -> Double {
    let last = x.lastIndex { abs($0) >= silenceThreshold } ?? -1
    return Double(x.count - 1 - last) / sampleRate * 1000
}

/// 解碼本機檔案（只取第一聲道）。AVAudioFile 會依 iTunSMPB / priming 資訊修剪 AAC 的 encoder delay。
func decodeChannel0(_ url: URL) throws -> (samples: [Float], sampleRate: Double) {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buffer)
    let ch0 = buffer.floatChannelData![0]
    return (Array(UnsafeBufferPointer(start: ch0, count: Int(buffer.frameLength))), format.sampleRate)
}
