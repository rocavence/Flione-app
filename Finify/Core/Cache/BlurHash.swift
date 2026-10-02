import CoreGraphics
import Foundation

/// BlurHash 解碼（https://github.com/woltapp/blurhash 演算法）。
/// Jellyfin 會為每張封面提供 BlurHash，用於圖片載入前的模糊 placeholder。
enum BlurHash {
    private static let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~")
    private static let lookup: [Character: Int] = Dictionary(uniqueKeysWithValues: characters.enumerated().map { ($1, $0) })
    nonisolated(unsafe) private static let cache = NSCache<NSString, CGImageBox>()

    static func image(_ hash: String, size: Int = 24) -> CGImage? {
        let key = "\(hash)-\(size)" as NSString
        if let hit = cache.object(forKey: key) { return hit.image }
        guard let image = decode(hash, width: size, height: size) else { return nil }
        cache.setObject(CGImageBox(image), forKey: key)
        return image
    }

    /// 封面的平均色，作為沒有 BlurHash 或尚未解碼時的底色
    static func averageColor(_ hash: String) -> (r: Double, g: Double, b: Double)? {
        let chars = Array(hash)
        guard chars.count >= 6, let value = decode83(chars[2..<6]) else { return nil }
        return (Double(value >> 16) / 255, Double((value >> 8) & 255) / 255, Double(value & 255) / 255)
    }

    static func decode(_ hash: String, width: Int, height: Int, punch: Double = 1) -> CGImage? {
        let chars = Array(hash)
        guard chars.count >= 6, let sizeFlag = decode83(chars[0..<1]) else { return nil }
        let numY = (sizeFlag / 9) + 1, numX = (sizeFlag % 9) + 1
        guard chars.count == 4 + 2 * numX * numY,
              let quantisedMax = decode83(chars[1..<2]) else { return nil }
        let maxValue = Double(quantisedMax + 1) / 166

        var colors: [(Double, Double, Double)] = []
        for i in 0..<(numX * numY) {
            if i == 0 {
                guard let value = decode83(chars[2..<6]) else { return nil }
                colors.append((srgbToLinear(value >> 16), srgbToLinear((value >> 8) & 255), srgbToLinear(value & 255)))
            } else {
                let start = 4 + i * 2
                guard let value = decode83(chars[start..<start + 2]) else { return nil }
                let r = value / (19 * 19), g = (value / 19) % 19, b = value % 19
                colors.append((signPow((Double(r) - 9) / 9, 2) * maxValue * punch,
                               signPow((Double(g) - 9) / 9, 2) * maxValue * punch,
                               signPow((Double(b) - 9) / 9, 2) * maxValue * punch))
            }
        }

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                var r = 0.0, g = 0.0, b = 0.0
                for j in 0..<numY {
                    for i in 0..<numX {
                        let basis = cos(.pi * Double(x) * Double(i) / Double(width)) * cos(.pi * Double(y) * Double(j) / Double(height))
                        let c = colors[i + j * numX]
                        r += c.0 * basis; g += c.1 * basis; b += c.2 * basis
                    }
                }
                let o = 4 * (x + y * width)
                pixels[o] = linearToSRGB(r); pixels[o + 1] = linearToSRGB(g); pixels[o + 2] = linearToSRGB(b)
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private static func decode83<S: Sequence>(_ chars: S) -> Int? where S.Element == Character {
        var value = 0
        for c in chars {
            guard let digit = lookup[c] else { return nil }
            value = value * 83 + digit
        }
        return value
    }

    private static func signPow(_ value: Double, _ exp: Double) -> Double {
        copysign(pow(abs(value), exp), value)
    }

    private static func srgbToLinear(_ value: Int) -> Double {
        let v = Double(value) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func linearToSRGBUnit(_ value: Double) -> Double {
        let v = max(0, min(1, value))
        return v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    private static func linearToSRGB(_ value: Double) -> UInt8 {
        UInt8(max(0, min(255, (linearToSRGBUnit(value) * 255 + 0.5).rounded(.down))))
    }
}
