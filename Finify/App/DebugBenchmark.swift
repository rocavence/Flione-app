#if DEBUG || BENCHMARK
import AppKit
import QuartzCore

/// 效能量測：自動捲動 Album Wall，記錄每一 frame 時間與記憶體，輸出 JSON 後關閉 app。
/// 啟動參數：`-FinifyBenchWall <輸出路徑>`（搭配 `-FinifyStartMode overflow`）
/// 量測方法與 S3 spike 相同，見 docs/spikes/S3-album-wall.md。
@MainActor
final class WallBenchmark: NSObject {
    private let output: URL
    private var scrollView: NSScrollView?
    private var link: CADisplayLink?
    private var start: CFTimeInterval = 0
    private var last: CFTimeInterval = 0
    private var frameDuration: CFTimeInterval = 1.0 / 60
    private var frames: [String: [Double]] = [:]
    private var memory: [Double] = []
    private var lastSample: CFTimeInterval = 0

    static func startIfRequested() {
        guard let path = UserDefaults.standard.string(forKey: "FinifyBenchWall") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard let window = NSApp.windows.first(where: \.isVisible), let content = window.contentView else { return }
            let bench = WallBenchmark(output: URL(fileURLWithPath: path))
            bench.scrollView = Self.findWallScrollView(in: content)
            bench.link = content.displayLink(target: bench, selector: #selector(tick(_:)))
            bench.link?.add(to: .main, forMode: .common)
            retained = bench
        }
    }

    private static var retained: WallBenchmark?

    init(output: URL) { self.output = output }

    private static func findWallScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView, scroll.documentView is NSCollectionView { return scroll }
        for sub in view.subviews { if let found = findWallScrollView(in: sub) { return found } }
        return nil
    }

    // 時間軸（秒）：0–20 往下捲到底，20–30 捲回頂端，30–33 閒置
    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if start == 0 { start = now; last = now; frameDuration = link.duration }
        let t = now - start
        let dt = (now - last) * 1000
        last = now
        let phase = t < 20 ? "scrollDown" : t < 30 ? "scrollUp" : "idle"
        if t > 0 { frames[phase, default: []].append(dt) }
        if now - lastSample > 0.5 { lastSample = now; memory.append(Self.footprintMB()) }
        switch phase {
        case "scrollDown": scroll(to: t / 20)
        case "scrollUp": scroll(to: 1 - (t - 20) / 10)
        default: if t > 33 { finish() }
        }
    }

    private func scroll(to progress: Double) {
        guard let scroll = scrollView, let doc = scroll.documentView else { return }
        let top = -scroll.contentInsets.top
        let maxY = max(top, doc.frame.height - scroll.contentView.bounds.height + scroll.contentInsets.bottom)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: top + (maxY - top) * min(max(progress, 0), 1)))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func finish() {
        link?.invalidate()
        func summary(_ dts: [Double]) -> [String: Double] {
            let sorted = dts.sorted(), total = dts.reduce(0, +), budget = frameDuration * 1000
            let hitch = dts.map { max(0, $0 - budget) }.filter { $0 > budget * 0.5 }.reduce(0, +)
            return ["avgFPS": Double(dts.count) / (total / 1000), "p99ms": sorted[Int(Double(sorted.count - 1) * 0.99)],
                    "maxms": sorted.last ?? 0, "hitchMsPerSec": hitch / (total / 1000)]
        }
        let result: [String: Any] = [
            "refreshHz": Int((1 / frameDuration).rounded()),
            "phases": frames.mapValues(summary),
            "memoryMB": ["start": memory.first ?? 0, "peak": memory.max() ?? 0, "end": memory.last ?? 0],
            "foundWall": scrollView != nil,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: output)
        }
        NSApp.terminate(nil)
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}
#endif
