// 產生 S3 用的假封面：300 張 600×600 JPEG，含漸層與雜訊，讓 decode 成本接近真實封面。
// 用法：swift Spikes/AlbumWall/make-artwork.swift <輸出資料夾>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
var rng = SystemRandomNumberGenerator()

for i in 0..<300 {
    let size = 600
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let h1 = Double(i % 37) / 37, h2 = Double((i * 7) % 41) / 41
    let c1 = NSColor(hue: h1, saturation: 0.6, brightness: 0.8, alpha: 1).cgColor
    let c2 = NSColor(hue: h2, saturation: 0.7, brightness: 0.3, alpha: 1).cgColor
    let g = CGGradient(colorsSpace: nil, colors: [c1, c2] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: size, y: size), options: [])
    for _ in 0..<40 {
        ctx.setFillColor(NSColor(hue: .random(in: 0...1, using: &rng), saturation: 0.5,
                                 brightness: .random(in: 0.2...1, using: &rng), alpha: 0.5).cgColor)
        let r = CGFloat.random(in: 20...200, using: &rng)
        ctx.fillEllipse(in: CGRect(x: .random(in: -50...600, using: &rng), y: .random(in: -50...600, using: &rng), width: r, height: r))
    }
    for _ in 0..<20000 {
        ctx.setFillColor(gray: .random(in: 0...1, using: &rng), alpha: 0.15)
        ctx.fill(CGRect(x: Int.random(in: 0..<size, using: &rng), y: Int.random(in: 0..<size, using: &rng), width: 2, height: 2))
    }
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])!
        .write(to: out.appendingPathComponent(String(format: "%03d.jpg", i)))
}
print("done")
