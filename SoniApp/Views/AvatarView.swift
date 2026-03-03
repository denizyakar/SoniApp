//
//  AvatarView.swift
//  SoniApp

import SwiftUI

struct AvatarView: View {
    let imageUrl: URL?
    let sfSymbol: String
    let size: CGFloat
    let showBackground: Bool
    
    init(imageUrl: URL? = nil, sfSymbol: String = "person.circle", size: CGFloat = 40, showBackground: Bool = true) {
        self.imageUrl = imageUrl
        self.sfSymbol = sfSymbol
        self.size = size
        self.showBackground = showBackground
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
                            .frame(width: size * 0.5, height: size * 0.5) // Smaller loader
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
        let baseImage = Image(systemName: sfSymbol)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(AppTheme.white)
            .padding(4)
        
        return Group {
            if showBackground {
                baseImage
                    .background(AppTheme.primaryLight)
                    .clipShape(Circle())
            } else {
                baseImage
                    .clipShape(Circle())
            }
        }
    }
}

// MARK: - Convenience initializers

extension AvatarView {
    /// Create avatar from UserItem
    init(userItem: UserItem, size: CGFloat = 40, showBackground: Bool = true) {
        self.init(
            imageUrl: userItem.avatarImageUrl,
            sfSymbol: userItem.avatarName.isEmpty ? "person.circle" : userItem.avatarName,
            size: size,
            showBackground: showBackground
        )
    }
    
    /// Create avatar from ChatUser
    init(chatUser: ChatUser, size: CGFloat = 40, showBackground: Bool = true) {
        self.init(
            imageUrl: chatUser.avatarImageUrl,
            sfSymbol: chatUser.avatar,
            size: size,
            showBackground: showBackground
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        AvatarView(sfSymbol: "person.circle", size: 60)
        AvatarView(sfSymbol: "star.circle.fill", size: 48)
        AvatarView(sfSymbol: "flame.circle", size: 28)
    }
    .padding()
    .background(AppTheme.background)
}
