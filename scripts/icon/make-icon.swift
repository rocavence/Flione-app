// 產生 Finify 的 app icon 與選單列 icon（Finity 設計）
// 字形：兩道水滴狀筆畫組成的「F」——第一道從底部往上、在左上轉彎成頂橫並收成尖尾，第二道是較短的中橫。
// 用法：
//   swift scripts/icon/make-icon.swift app <輸出 1024px PNG>
//   swift scripts/icon/make-icon.swift menubar <輸出資料夾>   # 產生 18pt 的 @1x/@2x/@3x，一般版（template）與播放中版
//   swift scripts/icon/make-icon.swift glyph <輸出 PNG>       # 字形預覽
import AppKit
import CoreImage

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func write(_ image: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

// MARK: - 字形

typealias Cubic = (CGPoint, CGPoint, CGPoint, CGPoint)

func point(_ c: Cubic, _ t: CGFloat) -> CGPoint {
    let u = 1 - t
    let a = u * u * u, b = 3 * u * u * t, d = 3 * u * t * t, e = t * t * t
    return CGPoint(x: a * c.0.x + b * c.1.x + d * c.2.x + e * c.3.x, y: a * c.0.y + b * c.1.y + d * c.2.y + e * c.3.y)
}

/// 沿中心線（一串三次曲線）畫出寬度會變的筆畫；width(s) 的 s 是 0…1 的弧長比例。起點是圓頭。
func stroke(_ curves: [Cubic], width: (CGFloat) -> CGFloat) -> CGPath {
    var pts: [CGPoint] = []
    for c in curves {
        for i in 0...120 where !(i == 0 && !pts.isEmpty) { pts.append(point(c, CGFloat(i) / 120)) }
    }
    var lengths: [CGFloat] = [0]
    for i in 1..<pts.count { lengths.append(lengths[i - 1] + hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)) }
    let total = lengths.last!
    var left: [CGPoint] = [], right: [CGPoint] = []
    for i in pts.indices {
        let a = pts[max(i - 1, 0)], b = pts[min(i + 1, pts.count - 1)]
        let dx = b.x - a.x, dy = b.y - a.y, len = max(hypot(dx, dy), 0.0001)
        let n = CGPoint(x: -dy / len, y: dx / len)
        let w = width(lengths[i] / total) / 2
        left.append(CGPoint(x: pts[i].x + n.x * w, y: pts[i].y + n.y * w))
        right.append(CGPoint(x: pts[i].x - n.x * w, y: pts[i].y - n.y * w))
    }
    let body = CGMutablePath()
    body.addLines(between: left + right.reversed())
    body.closeSubpath()
    // 兩端都是圓頭（尾端很小，看起來仍是水滴尖，但大尺寸不會像刀刃）
    var path: CGPath = body
    for (point, w) in [(pts[0], width(0)), (pts[pts.count - 1], width(1))] where w > 0 {
        let r = w / 2
        path = path.union(CGPath(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2), transform: nil))
    }
    return path
}

/// 水滴尾：u 從 0 到 1，兩側微微外凸，最後收成尖點
func drop(_ u: CGFloat) -> CGFloat { let v = min(max(u, 0), 1); return (1 - v) * (1 + 0.9 * v) }

/// 字形，座標在 100×100 的方框內（y 向上）
func glyph() -> CGPath {
    let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: x, y: y) }
    // 主筆畫：底部圓頭 → 往上 → 左上圓轉角 → 頂橫水滴尾。切線在接點連續，避免凸點
    let main = stroke([
        (p(30, 9), p(30, 27), p(30, 45), p(30, 60)),
        (p(30, 60), p(30, 79), p(36, 87.5), p(51, 87.5)),
        (p(51, 87.5), p(65, 87.5), p(79, 88), p(91, 89.5)),
    ]) { s in
        // 主幹 12.5，進入頂橫後鼓起成水滴（最寬 16.5），尾端收到 2.5
        if s < 0.5 { return 12.5 }
        if s < 0.66 { let k = (s - 0.5) / 0.16; return 12.5 + 4 * k * k * (3 - 2 * k) }
        return 2.5 + 14 * drop((s - 0.66) / 0.34)
    }
    // 中橫：圓頭埋在主幹裡，水滴尾往右略上揚
    let middle = stroke([(p(36, 53), p(50, 54), p(64, 55), p(77, 57.5))]) { s in 2.5 + 13 * drop(s) }
    return main.union(middle)
}

/// 二次曲線轉成三次曲線
func p3(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Cubic {
    (a, CGPoint(x: a.x + 2 / 3 * (b.x - a.x), y: a.y + 2 / 3 * (b.y - a.y)), CGPoint(x: c.x + 2 / 3 * (b.x - c.x), y: c.y + 2 / 3 * (b.y - c.y)), c)
}

func glyph(in rect: CGRect) -> CGPath {
    var t = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width / 100, y: rect.height / 100)
    return glyph().copy(using: &t)!
}

// MARK: - App icon

let ci = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

func ciImage(_ size: Int, draw: (CGContext) -> Void) -> CIImage {
    let ctx = makeContext(size, size)
    draw(ctx)
    return CIImage(cgImage: ctx.makeImage()!)
}

extension CIImage {
    func blurred(_ r: CGFloat) -> CIImage { clampedToExtent().applyingGaussianBlur(sigma: r).cropped(to: extent) }
    func moved(_ dx: CGFloat, _ dy: CGFloat) -> CIImage { transformed(by: CGAffineTransform(translationX: dx, y: dy)).cropped(to: extent) }
    /// 只留下 alpha，換成指定顏色
    func tinted(_ c: CGColor) -> CIImage {
        let comps = c.components!
        return applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: comps[3]),
            "inputBiasVector": CIVector(x: comps[0], y: comps[1], z: comps[2], w: 0),
        ])
    }
    /// 用另一張圖的 alpha 當遮罩
    func masked(by mask: CIImage) -> CIImage { applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: mask]) }
    /// self 扣掉 other 的 alpha
    func minus(_ other: CIImage) -> CIImage { applyingFilter("CISourceOutCompositing", parameters: [kCIInputBackgroundImageKey: other]) }
    func over(_ bg: CIImage) -> CIImage { composited(over: bg) }
}

func appIcon() -> CGImage {
    let size = 1024
    // macOS icon grid：824×824 的圓角方形置中，下方留陰影空間
    let bodyRect = CGRect(x: 100, y: 110, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: bodyRect, cornerWidth: 185, cornerHeight: 185, transform: nil)
    // 字形外框約落在 x 24…93、y 7…91，置中後再往左一點，讓視覺重心居中
    let glyphRect = CGRect(x: 512 - 300 - 48, y: 512 - 300 + 10, width: 600, height: 600)
    let glyphPath = glyph(in: glyphRect)

    // 1. 背景：左下深藍 → Finity Blue → 右上紫，右上一團粉白光、左下壓暗
    let background = ciImage(size) { ctx in
        ctx.addPath(bodyPath); ctx.clip()
        let g = CGGradient(colorsSpace: nil, colors: [color(0x0E2A9C), color(0x1D4ED8), color(0x2F6BFF), color(0x6A8DFF), color(0xA78BFA)] as CFArray,
                           locations: [0, 0.3, 0.55, 0.8, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: bodyRect.minX, y: bodyRect.minY), end: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY), options: [])
        let glow = CGGradient(colorsSpace: nil, colors: [color(0xFFE6F7, 0.85), color(0xD2C2FF, 0.4), color(0xA78BFA, 0)] as CFArray, locations: [0, 0.35, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 820, y: 860), startRadius: 0, endCenter: CGPoint(x: 820, y: 860), endRadius: 460, options: [])
        let shade = CGGradient(colorsSpace: nil, colors: [color(0x061344, 0.55), color(0x061344, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(shade, startCenter: CGPoint(x: 160, y: 140), startRadius: 0, endCenter: CGPoint(x: 160, y: 140), endRadius: 560, options: [])
    }

    let mask = ciImage(size) { ctx in ctx.addPath(glyphPath); ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath() }

    // 2. 落在背景上的柔和陰影（深藍，不用黑）
    let shadow = mask.tinted(color(0x06125A, 0.5)).blurred(28).moved(10, -28).minus(mask)
    // 透過玻璃看到的光：字形底下的背景稍微提亮、偏冰藍
    let glow = mask.tinted(color(0x9CC0FF, 0.35)).blurred(40).minus(mask)
    // 3. 半透明本體：上亮下透，讓背景色透出來
    let fill = ciImage(size) { ctx in
        let g = CGGradient(colorsSpace: nil, colors: [color(0xFFFFFF, 0.95), color(0xE9E4FF, 0.8), color(0xA9BDFF, 0.62), color(0x5B86FF, 0.55)] as CFArray, locations: [0, 0.3, 0.65, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: glyphRect.maxX, y: glyphRect.maxY), end: CGPoint(x: glyphRect.minX, y: glyphRect.minY), options: [])
    }.masked(by: mask)
    // 4. 厚度：左下內緣偏藍
    let depth = mask.minus(mask.moved(18, 18)).blurred(14).tinted(color(0x2F6BFF, 0.6)).masked(by: mask)
    // 凝膠內部的紫粉色散光
    let inner = ciImage(size) { ctx in
        let g = CGGradient(colorsSpace: nil, colors: [color(0xFFC9EE, 0.55), color(0xBDBDFF, 0.2), color(0xBDBDFF, 0)] as CFArray, locations: [0, 0.45, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: glyphRect.maxX - 120, y: glyphRect.maxY - 40), startRadius: 0,
                               endCenter: CGPoint(x: glyphRect.maxX - 120, y: glyphRect.maxY - 40), endRadius: 300, options: [])
    }.masked(by: mask)
    // 5. 內緣光：靠近邊緣處較亮，像凝膠
    let rim = mask.minus(mask.blurred(22)).tinted(color(0xFFFFFF, 0.4)).masked(by: mask)
    // 6. 右上高光
    let specular = mask.minus(mask.moved(-7, -9)).blurred(3).tinted(color(0xFFFFFF, 1)).masked(by: mask)
    // 7. 本體內部一點霧化的反光，讓表面不是平的
    let sheen = ciImage(size) { ctx in
        let g = CGGradient(colorsSpace: nil, colors: [color(0xFFFFFF, 0.35), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: glyphRect.midX + 120, y: glyphRect.maxY - 60), startRadius: 0,
                               endCenter: CGPoint(x: glyphRect.midX + 120, y: glyphRect.maxY - 60), endRadius: 340, options: [])
    }.masked(by: mask)

    let bodyMask = ciImage(size) { ctx in ctx.addPath(bodyPath); ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath() }
    let base = glow.masked(by: bodyMask).over(shadow.masked(by: bodyMask).over(background))
    let art = specular.over(rim.over(sheen.over(inner.over(depth.over(fill.over(base))))))

    let ctx = makeContext(size, size)
    // icon 本身的陰影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(bodyPath); ctx.setFillColor(color(0x1D4ED8)); ctx.fillPath()
    ctx.restoreGState()
    ctx.draw(ci.createCGImage(art, from: CGRect(x: 0, y: 0, width: size, height: size))!, in: CGRect(x: 0, y: 0, width: size, height: size))
    // 細亮邊，讓 icon 在深色 Dock 上有輪廓
    ctx.addPath(CGPath(roundedRect: bodyRect.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 184, cornerHeight: 184, transform: nil))
    ctx.setStrokeColor(color(0xFFFFFF, 0.16)); ctx.setLineWidth(3); ctx.strokePath()
    return ctx.makeImage()!
}

// MARK: - 選單列 icon

/// 18×18pt 畫布，字形高約 16pt、靠左置中；playing 時右下加一個播放中的小點
func menuBarIcon(scale: Int, playing: Bool) -> CGImage {
    let pt: CGFloat = 18, px = Int(pt) * scale
    let ctx = makeContext(px, px)
    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    // 字形外框 y 7…91（84 單位）→ 16pt 高；x 24…93 → 約 13pt 寬
    let unit: CGFloat = 16 / 84
    let origin = CGPoint(x: (playing ? 7.2 : 9) - 58.5 * unit, y: 1 - 7 * unit)
    ctx.addPath(glyph(in: CGRect(x: origin.x, y: origin.y, width: 100 * unit, height: 100 * unit)))
    if playing {
        ctx.addEllipse(in: CGRect(x: 14.2, y: 1.2, width: 3.2, height: 3.2))
    }
    // 小尺寸時描邊 0.5pt 加粗，筆畫重量接近系統選單列 icon
    let ink = playing ? color(0x3E7CF6) : color(0x000000)
    ctx.setFillColor(ink); ctx.setStrokeColor(ink); ctx.setLineWidth(0.5); ctx.setLineJoin(.round)
    ctx.drawPath(using: .fillStroke)
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
    let props = template ? #","properties" : { "template-rendering-intent" : "template" }"# : ""
    let json = "{\n  \"images\" : [\n" + images.joined(separator: ",\n") + "\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\(props)\n}\n"
    try! json.write(toFile: "\(set)/Contents.json", atomically: true, encoding: .utf8)
}

// MARK: - 輸出

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "glyph":
    let ctx = makeContext(800, 800)
    ctx.setFillColor(color(0xFFFFFF)); ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 800))
    ctx.addPath(glyph(in: CGRect(x: 0, y: 0, width: 800, height: 800)))
    ctx.setFillColor(color(0x000000)); ctx.fillPath()
    write(ctx.makeImage()!, args[2])
case "menubar":
    writeImageSet(args[2], name: "MenuBarIcon", template: true, playing: false)
    writeImageSet(args[2], name: "MenuBarIconPlaying", template: false, playing: true)
case "app":
    write(appIcon(), args[2])
default:
    print("用法：make-icon.swift app|menubar|glyph <輸出>")
}
