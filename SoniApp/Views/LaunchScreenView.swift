import SwiftUI

struct LaunchScreenView: View {
    @State private var progress: CGFloat = 0.0
    
    // Primary accent color:
    private let backgroundColor = AppTheme.primary
    
    var body: some View {
        ZStack {
            // Background
            AppTheme.backgroundLight
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // Logo area
                Image("logo")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 250.0, height: 250)
                    .cornerRadius(12)
                
                // App Name
                Text("SoniApp")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.white.opacity(0.9))
                    .padding(.top, 20)
                
                Spacer()
                
                // Progress Bar
                ZStack(alignment: .leading) {
                    ZStack {
                        // 1. White box (background, acts as border)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 270, height: 25)
                        
                        // 2. Inner black background + filling blue bar
                        ZStack(alignment: .leading) {
                            // Black background
                            Rectangle()
                                .fill(Color.black)
                                .frame(width: 250, height: 12)
                            
                            // Filling blue bar
                            Rectangle()
                                .fill(AppTheme.primary)
                                .frame(width: 250 * progress, height: 12)
                        }
                        .frame(width: 250, height: 10)
                    }

                        
                }
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            // Simple 1.5s fill animation
            withAnimation(.easeInOut(duration: 1.5)) {
                progress = 1.0
            }
        }
    }
}

#Preview {
    LaunchScreenView()
}
