// 產生 Finify 的 app icon 與選單列 icon（Finity 設計）
// app icon 直接使用設計稿 scripts/icon/finity-icon-source.png，裁成 macOS icon 尺寸並加上圓角與陰影；
// 選單列 icon 是設計稿裡兩個水滴的實心輪廓（座標描自設計稿，1254px、y 向下）。
// 用法：
//   swift scripts/icon/make-icon.swift app <設計稿 PNG> <輸出 1024px PNG>
//   swift scripts/icon/make-icon.swift menubar <輸出資料夾>   # 18pt 的 @1x/@2x/@3x，一般版（template）與播放中版
//   swift scripts/icon/make-icon.swift glyph <輸出 PNG>       # 字形預覽
import AppKit

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func write(_ image: CGImage, _ path: String) {
    try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

// MARK: - 字形

/// 兩個水滴：上方的水滴圓頭在右上、尾巴收進左下；下方的水滴圓頭在左下、尾巴往右成為中橫
let drops: [(start: CGPoint, segments: [(CGPoint, CGPoint, CGPoint)])] = [
    (CGPoint(x: 425, y: 525), [
        (CGPoint(x: 470, y: 330), CGPoint(x: 800, y: 170), CGPoint(x: 1010, y: 205)),
        (CGPoint(x: 1115, y: 225), CGPoint(x: 1120, y: 410), CGPoint(x: 985, y: 440)),
        (CGPoint(x: 810, y: 475), CGPoint(x: 620, y: 410), CGPoint(x: 425, y: 525)),
    ]),
    (CGPoint(x: 975, y: 590), [
        (CGPoint(x: 900, y: 560), CGPoint(x: 700, y: 470), CGPoint(x: 520, y: 505)),
        (CGPoint(x: 330, y: 545), CGPoint(x: 200, y: 700), CGPoint(x: 215, y: 860)),
        (CGPoint(x: 225, y: 1000), CGPoint(x: 330, y: 1070), CGPoint(x: 400, y: 1065)),
        (CGPoint(x: 490, y: 1060), CGPoint(x: 560, y: 980), CGPoint(x: 550, y: 860)),
        (CGPoint(x: 545, y: 780), CGPoint(x: 590, y: 740), CGPoint(x: 680, y: 755)),
        (CGPoint(x: 820, y: 780), CGPoint(x: 935, y: 715), CGPoint(x: 975, y: 590)),
    ]),
]

/// 字形放進 rect（y 向上），維持比例置中
func glyph(in rect: CGRect) -> CGPath {
    let raw = CGMutablePath()
    for drop in drops {
        raw.move(to: drop.start)
        for (c1, c2, end) in drop.segments { raw.addCurve(to: end, control1: c1, control2: c2) }
        raw.closeSubpath()
    }
    let box = raw.boundingBoxOfPath
    let scale = min(rect.width / box.width, rect.height / box.height)
    // 設計稿 y 向下，翻成 y 向上
    var t = CGAffineTransform(translationX: rect.midX, y: rect.midY)
        .scaledBy(x: scale, y: -scale)
        .translatedBy(x: -box.midX, y: -box.midY)
    return raw.copy(using: &t)!
}

// MARK: - App icon

func appIcon(source: String) -> CGImage {
    let src = NSImage(contentsOfFile: source)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    // 設計稿裡圓角方形的範圍（白底以外）
    let square = CGRect(x: 56, y: 53, width: 1142, height: 1141)
    let crop = src.cropping(to: square)!
    let size = 1024
    // macOS icon grid：824×824 的圓角方形置中，下方留陰影空間
    let body = CGRect(x: 100, y: 110, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    let ctx = makeContext(size, size)
    ctx.interpolationQuality = .high
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(bodyPath); ctx.setFillColor(color(0x1D4ED8)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    // 稍微放大，讓設計稿四角的白底落在遮罩外
    ctx.draw(crop, in: body.insetBy(dx: -10, dy: -10))
    ctx.restoreGState()
    return ctx.makeImage()!
}

// MARK: - 選單列 icon

/// 18×18pt 畫布、字形 16pt；playing 時右下（F 的空白處）加一個播放中的小點
func menuBarIcon(scale: Int, playing: Bool) -> CGImage {
    let pt: CGFloat = 18
    let ctx = makeContext(Int(pt) * scale, Int(pt) * scale)
    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    ctx.addPath(glyph(in: CGRect(x: 1, y: 1, width: 16, height: 16)))
    if playing { ctx.addEllipse(in: CGRect(x: 13.6, y: 1.4, width: 3.2, height: 3.2)) }
    ctx.setFillColor(playing ? color(0x3E7CF6) : color(0x000000))
    ctx.fillPath()
    return ctx.makeImage()!
}

func writeImageSet(_ dir: String, name: String, template: Bool, playing: Bool) {
    let set = "\(dir)/\(name).imageset"
    try! FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
    var images: [String] = []
    for scale in 1...3 {
        let file = "\(name)@\(scale)x.png"
        write(menuBarIcon(scale: scale, playing: playing), "\(set)/\(file)")
        images.append(#"    { "filename" : "\#(file)", "idiom" : "universal", "scale" : "\#(scale)x" }"#)
    }
    let props = template ? #",\#n  "properties" : { "template-rendering-intent" : "template" }"# : ""
    let json = "{\n  \"images\" : [\n" + images.joined(separator: ",\n") + "\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\(props)\n}\n"
    try! json.write(toFile: "\(set)/Contents.json", atomically: true, encoding: .utf8)
}

// MARK: - 輸出

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "glyph":
    let ctx = makeContext(800, 800)
    ctx.setFillColor(color(0xFFFFFF)); ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 800))
    ctx.addPath(glyph(in: CGRect(x: 50, y: 50, width: 700, height: 700)))
    ctx.setFillColor(color(0x000000)); ctx.fillPath()
    write(ctx.makeImage()!, args[2])
case "menubar":
    writeImageSet(args[2], name: "MenuBarIcon", template: true, playing: false)
    writeImageSet(args[2], name: "MenuBarIconPlaying", template: false, playing: true)
case "app":
    write(appIcon(source: args[2]), args[3])
default:
    print("用法：make-icon.swift app <設計稿> <輸出> | menubar <資料夾> | glyph <輸出>")
}
