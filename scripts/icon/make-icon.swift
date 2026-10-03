// 產生 Finify 的 app icon 與選單列 icon（Finity 設計）
// app icon：設計稿 scripts/icon/finity-icon-source.png 依 macOS icon 格線標準化——824×824 圓角方形置中於 1024 畫布，加上標準陰影。
// 選單列：scripts/icon/menubar-glyph.svg（由 menubar-source.png 以 potrace 描出的向量路徑）。
// 用法：
//   swift scripts/icon/make-icon.swift app <設計稿 PNG> <輸出 1024px PNG>
//   swift scripts/icon/make-icon.swift menubar <字形 SVG> <輸出資料夾>   # 18pt 的 @1x/@2x/@3x，一般版（template）與播放中版
//   swift scripts/icon/make-icon.swift glyph <字形 SVG> <輸出 PNG>       # 字形預覽
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

// MARK: - 字形（SVG path，只支援 potrace 會輸出的 M/m、L/l、C/c、Z/z）

func parsePath(_ d: String) -> CGPath {
    let path = CGMutablePath()
    var tokens: [String] = []
    var current = ""
    for ch in d {
        if ch.isLetter {
            if !current.isEmpty { tokens.append(current); current = "" }
            tokens.append(String(ch))
        } else if ch == " " || ch == "," || ch == "\n" {
            if !current.isEmpty { tokens.append(current); current = "" }
        } else if ch == "-", !current.isEmpty, current.last != "e" {
            tokens.append(current); current = "-"
        } else {
            current.append(ch)
        }
    }
    if !current.isEmpty { tokens.append(current) }

    var i = 0, command = "M"
    var point = CGPoint.zero, start = CGPoint.zero
    func number() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i])!) }
    while i < tokens.count {
        if Double(tokens[i]) == nil { command = tokens[i]; i += 1 }
        let relative = command == command.lowercased()
        let base = relative ? point : .zero
        switch command.uppercased() {
        case "M":
            point = CGPoint(x: base.x + number(), y: base.y + number())
            path.move(to: point); start = point
            command = relative ? "l" : "L"  // M 後面接的座標當作 L
        case "L":
            point = CGPoint(x: base.x + number(), y: base.y + number())
            path.addLine(to: point)
        case "C":
            let c1 = CGPoint(x: base.x + number(), y: base.y + number())
            let c2 = CGPoint(x: base.x + number(), y: base.y + number())
            point = CGPoint(x: base.x + number(), y: base.y + number())
            path.addCurve(to: point, control1: c1, control2: c2)
        case "Z":
            path.closeSubpath(); point = start
        default:
            fatalError("不支援的 SVG 指令：\(command)")
        }
    }
    return path
}

/// 讀 menubar-glyph.svg 的 path，放進 rect（y 向上），維持比例置中
func glyph(svg: String, in rect: CGRect) -> CGPath {
    let text = try! String(contentsOfFile: svg, encoding: .utf8)
    let d = text.components(separatedBy: " d=\"")[1].components(separatedBy: "\"")[0]
    let raw = parsePath(d)  // potrace 座標已是 y 向上
    let box = raw.boundingBoxOfPath
    let scale = min(rect.width / box.width, rect.height / box.height)
    var t = CGAffineTransform(translationX: rect.midX, y: rect.midY).scaledBy(x: scale, y: scale).translatedBy(x: -box.midX, y: -box.midY)
    return raw.copy(using: &t)!
}

// MARK: - App icon

/// 設計稿四周若有白底，只取非白色的範圍；滿版的設計稿就整張使用
func contentRect(of image: CGImage) -> CGRect {
    let w = image.width, h = image.height
    let ctx = makeContext(w, h)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let data = ctx.data!.assumingMemoryBound(to: UInt8.self), row = ctx.bytesPerRow
    var minX = w, minY = h, maxX = 0, maxY = 0
    for y in 0..<h {
        for x in 0..<w {
            let p = data + y * row + x * 4
            if min(p[0], p[1], p[2]) < 235 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
        }
    }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

func appIcon(source: String) -> CGImage {
    let src = NSImage(contentsOfFile: source)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let art = src.cropping(to: contentRect(of: src))!
    let size = 1024
    // macOS icon 格線：824×824 的圓角方形，置中，下方留陰影空間
    let body = CGRect(x: 100, y: 110, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    let ctx = makeContext(size, size)
    ctx.interpolationQuality = .high
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(bodyPath); ctx.setFillColor(color(0x050A1E)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    ctx.draw(art, in: body)
    ctx.restoreGState()
    // 細亮邊，讓深色 icon 在深色 Dock 上有輪廓
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 1, dy: 1), cornerWidth: 184, cornerHeight: 184, transform: nil))
    ctx.setStrokeColor(color(0xFFFFFF, 0.12)); ctx.setLineWidth(2); ctx.strokePath()
    return ctx.makeImage()!
}

// MARK: - 選單列 icon

/// 18×18pt 畫布、字形 16pt 置中；playing 時右下加一個播放中的小點
func menuBarIcon(svg: String, scale: Int, playing: Bool) -> CGImage {
    let pt: CGFloat = 18
    let ctx = makeContext(Int(pt) * scale, Int(pt) * scale)
    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    ctx.addPath(glyph(svg: svg, in: CGRect(x: 1, y: 1, width: 16, height: 16)))
    if playing { ctx.addEllipse(in: CGRect(x: 13.8, y: 0.6, width: 3.2, height: 3.2)) }
    ctx.setFillColor(playing ? color(0x3E7CF6) : color(0x000000))
    ctx.fillPath()
    return ctx.makeImage()!
}

func writeImageSet(_ dir: String, svg: String, name: String, template: Bool, playing: Bool) {
    let set = "\(dir)/\(name).imageset"
    try! FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
    var images: [String] = []
    for scale in 1...3 {
        let file = "\(name)@\(scale)x.png"
        write(menuBarIcon(svg: svg, scale: scale, playing: playing), "\(set)/\(file)")
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
    ctx.addPath(glyph(svg: args[2], in: CGRect(x: 50, y: 50, width: 700, height: 700)))
    ctx.setFillColor(color(0x000000)); ctx.fillPath()
    write(ctx.makeImage()!, args[3])
case "menubar":
    writeImageSet(args[3], svg: args[2], name: "MenuBarIcon", template: true, playing: false)
    writeImageSet(args[3], svg: args[2], name: "MenuBarIconPlaying", template: false, playing: true)
case "app":
    write(appIcon(source: args[2]), args[3])
default:
    print("用法：make-icon.swift app <設計稿> <輸出> | menubar <字形 SVG> <資料夾> | glyph <字形 SVG> <輸出>")
}
