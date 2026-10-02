import AppKit
import QuartzCore

/// 自動捲動 Album Wall，記錄每一 frame 的時間與記憶體，結束後輸出 JSON 並結束 app。
@MainActor
final class Benchmark: NSObject {
    private enum Phase: String { case settle, scrollDown, densitySwitch, scrollUp, idle, done }

    private let model: WallModel
    private let output: URL
    private var scrollView: NSScrollView?
    private var link: CADisplayLink?
    private var start: CFTimeInterval = 0
    private var last: CFTimeInterval = 0
    private var frameDuration: CFTimeInterval = 1.0 / 60
    private var frames: [String: [Double]] = [:]
    private var switchFrames: [Double] = []
    private var lastSwitch: CFTimeInterval = -1
    private var memory: [(t: Double, mb: Double)] = []
    private var lastMemorySample: CFTimeInterval = 0

    init(model: WallModel, output: URL) {
        self.model = model
        self.output = output
    }

    func run(in window: NSWindow) {
        guard let content = window.contentView else { return }
        scrollView = Self.findScrollView(in: content)
        let link = content.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private static func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews { if let found = findScrollView(in: sub) { return found } }
        return nil
    }

    // 時間軸（秒）：0–2 settle，2–22 往下捲到底，22–31 切換 density，31–41 捲回頂端，41–44 閒置
    private func phase(at t: Double) -> Phase {
        switch t {
        case ..<2: .settle
        case ..<22: .scrollDown
        case ..<31: .densitySwitch
        case ..<41: .scrollUp
        case ..<44: .idle
        default: .done
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if start == 0 { start = now; last = now; frameDuration = link.duration }
        let t = now - start
        let dt = (now - last) * 1000
        last = now
        let phase = phase(at: t)

        if phase != .settle && phase != .done { frames[phase.rawValue, default: []].append(dt) }
        if lastSwitch >= 0, now - lastSwitch < 0.5 { switchFrames.append(dt) }

        if now - lastMemorySample > 0.25 {
            lastMemorySample = now
            memory.append((t, Self.footprintMB()))
        }

        switch phase {
        case .scrollDown: scroll(to: (t - 2) / 20)
        case .densitySwitch:
            let target: Density = t < 25 ? .medium : t < 27 ? .large : t < 29 ? .small : .medium
            if model.density != target {
                model.density = target
                lastSwitch = now
            }
        case .scrollUp: scroll(to: 1 - (t - 31) / 10)
        case .done: finish()
        default: break
        }
    }

    private func scroll(to progress: Double) {
        guard let scroll = scrollView, let doc = scroll.documentView else { return }
        let maxY = max(0, doc.frame.height - scroll.contentView.bounds.height)
        let y = maxY * min(max(progress, 0), 1)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: doc.isFlipped ? y : maxY - y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func finish() {
        link?.invalidate()
        link = nil

        func summary(_ dts: [Double]) -> [String: Double] {
            guard !dts.isEmpty else { return [:] }
            let sorted = dts.sorted()
            let total = dts.reduce(0, +)
            let budget = frameDuration * 1000
            let hitchMS = dts.map { max(0, $0 - budget) }.filter { $0 > budget * 0.5 }.reduce(0, +)
            return [
                "frames": Double(dts.count),
                "avgFPS": Double(dts.count) / (total / 1000),
                "p95ms": sorted[Int(Double(sorted.count - 1) * 0.95)],
                "p99ms": sorted[Int(Double(sorted.count - 1) * 0.99)],
                "maxms": sorted.last!,
                "hitchMsPerSec": hitchMS / (total / 1000),
            ]
        }

        let stats = model.pipeline.snapshot
        let afterSettle = memory.filter { $0.t >= 2 }
        let result: [String: Any] = [
            "impl": model.impl.rawValue,
            "albums": model.albums.count,
            "budgetMB": model.pipeline.cache.totalCostLimit / 1024 / 1024,
            "refreshHz": Int((1 / frameDuration).rounded()),
            "phases": frames.mapValues(summary),
            "densitySwitch": summary(switchFrames),
            "memoryMB": [
                "atStart": afterSettle.first?.mb ?? 0,
                "peak": memory.map(\.mb).max() ?? 0,
                "end": memory.last?.mb ?? 0,
                "timeline": stride(from: 0, to: memory.count, by: 4).map { Int(memory[$0].mb) },
            ],
            "pipeline": [
                "requested": stats.requested,
                "decoded": stats.decoded,
                "cancelled": stats.cancelled,
                "cacheHits": stats.cacheHits,
            ],
        ]
        let data = try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try? data.write(to: output)
        NSApp.terminate(nil)
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}
