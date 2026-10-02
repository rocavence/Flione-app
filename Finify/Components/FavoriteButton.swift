import SwiftUI

/// 愛心：喜愛時用 Filled + accent
struct FavoriteButton: View {
    let itemID: String
    let name: String
    var size: FinifyIcon.Size = .compact
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let isFavorite = app.favorites.contains(itemID)
        FinifyIconButton(icon: .heart, label: isFavorite ? "Remove \(name) from Favorites" : "Add \(name) to Favorites",
                         size: size, isActive: isFavorite) {
            app.favorites.toggle(itemID)
        }
    }
}
