//
//  FullScreenAvatarOverlay.swift
//  SoniApp
//

import SwiftUI

struct FullScreenAvatarOverlay: View {
    @Binding var isPresented: Bool
    let imageUrl: URL?
    let sfSymbol: String
    
    private let displaySize: CGFloat = 280
    
    var body: some View {
        if isPresented {
            ZStack {
                // Dimmed background
                Color.black.opacity(0.8)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }
                
                // Enlarged photo — no AvatarView, no grey frame
                Group {
                    if let url = imageUrl {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: displaySize, height: displaySize)
                                    .clipShape(Circle())
                            case .failure:
                                fallbackIcon
                            case .empty:
                                ProgressView()
                                    .tint(.white)
                                    .frame(width: displaySize, height: displaySize)
                            @unknown default:
                                fallbackIcon
                            }
                        }
                    } else {
                        fallbackIcon
                    }
                }
                .shadow(radius: 20)
                .onTapGesture { dismiss() }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
            .zIndex(999)
        }
    }
    
    private var fallbackIcon: some View {
        Image(systemName: sfSymbol)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(.white)
            .frame(width: displaySize * 0.5, height: displaySize * 0.5)
    }
    
    private func dismiss() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isPresented = false
        }
    }
}
