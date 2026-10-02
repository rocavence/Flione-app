import CoreGraphics

enum Radius {
    static let small: CGFloat = 4
    static let ui: CGFloat = 8
    static let card: CGFloat = 12
    static let large: CGFloat = 16
    static let hero: CGFloat = 24
    static let floating: CGFloat = 32
    /// Artwork 本身限制在 0–12，預設用 small
    static let artwork: CGFloat = 4
}
