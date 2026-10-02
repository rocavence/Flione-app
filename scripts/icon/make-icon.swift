// 產生 Finify app icon（暫定版）：3×3 專輯格，亮起的格子組成「F」。
// 用法：swift scripts/icon/make-icon.swift <輸出 1024px PNG>
import AppKit

let size: CGFloat = 1024
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// macOS icon grid：824×824 的圓角方形置中，下方留陰影空間
let body = CGRect(x: 100, y: 100 + 10, width: 824, height: 824)
let radius: CGFloat = 185
let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(bodyPath)
ctx.setFillColor(color(0x0E0D0C))
ctx.fillPath()
ctx.restoreGState()

// 底色：極淡的暖色漸層
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
let bg = CGGradient(colorsSpace: nil, colors: [color(0x1D1A17), color(0x0B0A09)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])

// 3×3 專輯格
let inset: CGFloat = 132, gap: CGFloat = 34
let cell = (body.width - inset * 2 - gap * 2) / 3
// row 0 = 上排；「F」：上排全亮、中排左兩格、下排左一格
let lit: Set<[Int]> = [[0, 0], [0, 1], [0, 2], [1, 0], [1, 1], [2, 0]]
let palette: [[Int]: (UInt32, UInt32)] = [
    [0, 0]: (0xFF8A4C, 0xE0502A), [0, 1]: (0xFF6A3D, 0xC9402A), [0, 2]: (0xFFB15C, 0xFF6A3D),
    [1, 0]: (0xF2643A, 0xB8381F), [1, 1]: (0xFFC37A, 0xF08A3C), [2, 0]: (0xE0502A, 0x9E2F1C),
]
for row in 0..<3 {
    for col in 0..<3 {
        let x = body.minX + inset + CGFloat(col) * (cell + gap)
        let y = body.maxY - inset - CGFloat(row + 1) * cell - CGFloat(row) * gap
        let rect = CGRect(x: x, y: y, width: cell, height: cell)
        let path = CGPath(roundedRect: rect, cornerWidth: 18, cornerHeight: 18, transform: nil)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        if let (top, bottom) = palette[[row, col]], lit.contains([row, col]) {
            let g = CGGradient(colorsSpace: nil, colors: [color(top), color(bottom)] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
        } else {
            ctx.setFillColor(color(0xF4F1EC, 0.07))
            ctx.fill(rect)
        }
        ctx.restoreGState()
    }
}
ctx.restoreGState()

// 細邊框，讓深色 icon 在深色 Dock 上有輪廓
ctx.addPath(bodyPath)
ctx.setStrokeColor(color(0xFFFFFF, 0.08))
ctx.setLineWidth(3)
ctx.strokePath()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
