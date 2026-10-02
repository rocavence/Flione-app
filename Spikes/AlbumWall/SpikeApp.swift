import SwiftUI

// S3 Album Wall spike
// 參數（UserDefaults 格式，單一橫線）：-impl swiftui|appkit  -albums 10000  -budget-mb 150  -artwork <dir>  -out <json>
// 有 -out 時自動跑 benchmark，結束後輸出結果並關閉。

enum Impl: String { case swiftui, appkit }

@MainActor @Observable
final class WallModel {
    let impl: Impl
    let albums: [Album]
    let pipeline: ArtworkPipeline
    var density: Density = .medium

    init() {
        let args = UserDefaults.standard
        impl = Impl(rawValue: args.string(forKey: "impl") ?? "") ?? .appkit
        let count = args.integer(forKey: "albums")
        albums = (0..<(count > 0 ? count : 10_000)).map(Album.init)
        let budget = args.integer(forKey: "budget-mb")
        pipeline = ArtworkPipeline(
            directory: URL(fileURLWithPath: args.string(forKey: "artwork") ?? ".cache/spike-artwork"),
            budgetMB: budget > 0 ? budget : 150,
            latency: 0.03...0.15
        )
    }
}

@main
struct AlbumWallSpikeApp: App {
    @State private var model = WallModel()

    var body: some Scene {
        WindowGroup {
            WallRoot(model: model)
                .frame(width: 1440, height: 900)
        }
        .windowResizability(.contentSize)
    }
}

private struct WallRoot: View {
    let model: WallModel
    @State private var benchmark: Benchmark?

    var body: some View {
        Group {
            switch model.impl {
            case .swiftui: SwiftUIWall(albums: model.albums, density: model.density, pipeline: model.pipeline)
            case .appkit: AppKitWall(albums: model.albums, density: model.density, pipeline: model.pipeline)
            }
        }
        .background(.black)
        .task {
            guard let out = UserDefaults.standard.string(forKey: "out") else { return }
            try? await Task.sleep(for: .milliseconds(300))
            NSApp.activate()
            guard let window = NSApp.windows.first(where: \.isVisible) else { return }
            let bench = Benchmark(model: model, output: URL(fileURLWithPath: out))
            benchmark = bench
            bench.run(in: window)
        }
    }
}
