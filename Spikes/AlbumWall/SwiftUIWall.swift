import SwiftUI

/// 方案 A：SwiftUI ScrollView + LazyVGrid
struct SwiftUIWall: View {
    let albums: [Album]
    let density: Density
    let pipeline: ArtworkPipeline

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: density.side, maximum: density.side), spacing: 8)], spacing: 8) {
                ForEach(albums) { album in
                    SwiftUIWallCell(album: album, density: density, pipeline: pipeline)
                }
            }
            .padding(16)
        }
    }
}

private struct SwiftUIWallCell: View {
    let album: Album
    let density: Density
    let pipeline: ArtworkPipeline
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Color(hue: album.placeholderHue, saturation: 0.4, brightness: 0.5)
            if let image {
                Image(decorative: image, scale: 2).resizable()
            }
        }
        .frame(width: density.side, height: density.side)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: density) {
            image = pipeline.cached(album, px: density.pixelSize)
            if image == nil {
                image = await pipeline.load(album, px: density.pixelSize)
            }
        }
    }
}
