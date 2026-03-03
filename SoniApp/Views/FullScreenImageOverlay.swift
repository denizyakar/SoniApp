//
//  FullScreenImageOverlay.swift
//  SoniApp
//

import SwiftUI

/// Enlarges a chat photo (rectangular) when tapped.
struct FullScreenImageOverlay: View {
    @Binding var isPresented: Bool
    let imageUrl: URL?
    
    var body: some View {
        if isPresented {
            ZStack {
                Color.black.opacity(0.85)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }
                
                if let url = imageUrl {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: UIScreen.main.bounds.width - 32)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(radius: 20)
                        case .failure:
                            Image(systemName: "photo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 80, height: 80)
                                .foregroundColor(.white.opacity(0.5))
                        case .empty:
                            ProgressView()
                                .tint(.white)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .onTapGesture { dismiss() }
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
            .zIndex(999)
        }
    }
    
    private func dismiss() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isPresented = false
        }
    }
}
