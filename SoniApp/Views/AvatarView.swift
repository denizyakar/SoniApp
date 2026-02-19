//
//  AvatarView.swift
//  SoniApp
//
//  Reusable avatar component: fotoğraf varsa AsyncImage, yoksa SF Symbol.
//

import SwiftUI

/// Tüm ekranlarda kullanılan avatar gösterim bileşeni.
///
/// Öncelik sırası:
/// 1. `imageUrl` varsa → AsyncImage (sunucudan fotoğraf)
/// 2. `sfSymbol` varsa → Image(systemName:)
/// 3. Hiçbiri yoksa → "person.circle" varsayılan
struct AvatarView: View {
    let imageUrl: URL?
    let sfSymbol: String
    let size: CGFloat
    
    init(imageUrl: URL? = nil, sfSymbol: String = "person.circle", size: CGFloat = 40) {
        self.imageUrl = imageUrl
        self.sfSymbol = sfSymbol
        self.size = size
    }
    
    var body: some View {
        Group {
            if let url = imageUrl {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        sfSymbolView
                    case .empty:
                        ProgressView()
                            .frame(width: size * 0.5, height: size * 0.5) // Loader daha küçük olsun
                    @unknown default:
                        sfSymbolView
                    }
                }
            } else {
                sfSymbolView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
    
    private var sfSymbolView: some View {
        Image(systemName: sfSymbol)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(.blue)
            .padding(4) // SF Symbol biraz padding ister
            .background(Color.blue.opacity(0.1)) // Arka plan
            .clipShape(Circle())
    }
}

// MARK: - Convenience initializers

extension AvatarView {
    /// UserItem'dan avatar oluştur
    init(userItem: UserItem, size: CGFloat = 40) {
        self.init(
            imageUrl: userItem.avatarImageUrl,
            sfSymbol: userItem.avatarName.isEmpty ? "person.circle" : userItem.avatarName,
            size: size
        )
    }
    
    /// ChatUser'dan avatar oluştur
    init(chatUser: ChatUser, size: CGFloat = 40) {
        self.init(
            imageUrl: chatUser.avatarImageUrl,
            sfSymbol: chatUser.avatar,
            size: size
        )
    }
}
