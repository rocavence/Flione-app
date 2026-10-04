import SwiftUI

/// 愛心：喜愛時用 Filled + accent
struct FavoriteButton: View {
    let itemID: String
    let name: String
    var size: FlioneIcon.Size = .compact
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let isFavorite = app.favorites.contains(itemID)
        FlioneIconButton(icon: .heart, label: isFavorite ? "Remove \(name) from Favorites" : "Add \(name) to Favorites",
                         size: size, isActive: isFavorite) {
            Haptics.perform(.toggle)
            app.favorites.toggle(itemID)
        }
        .disabled(itemID.hasPrefix(Track.placeholderPrefix))
    }
}
