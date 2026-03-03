//
//  SoniAppApp.swift
//  SoniApp
//

import SwiftUI
import SwiftData

@main
struct ChatAppApp: App {
    
    @StateObject private var container = DependencyContainer()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @State private var isSplashFinished = false
    
    init() { }
    
    var body: some Scene {
        WindowGroup {
            if isSplashFinished {
                RootView()
                    .environmentObject(container)
                    .environmentObject(container.callManager)
                    .preferredColorScheme(.dark)
            } else {
                LaunchScreenView()
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                isSplashFinished = true
                            }
                        }
                    }
            }
        }
        .modelContainer(for: [MessageItem.self, UserItem.self])
    }
}

/// Main routing view. Observes `CallManager.callPhase` to show
/// the call screen via fullScreenCover when a call is in progress.
struct RootView: View {
    @EnvironmentObject var container: DependencyContainer
    @EnvironmentObject var callManager: CallManager
    
    var body: some View {
        Group {
            if container.isAuthenticated {
                ChatListView()
            } else {
                AuthView()
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { callManager.callPhase.shouldShowCallScreen },
            set: { newValue in
                if !newValue {
                    callManager.dismissCall()
                }
            }
        )) {
            if let data = callManager.incomingCallData,
               let opponentId = data["callerId"] as? String,
               let callerName = data["callerName"] as? String,
               let avatarUrl = data["callerAvatarUrl"] as? String {
                CallView(opponentId: opponentId, opponentName: callerName, opponentAvatarUrl: avatarUrl)
            } else {
                let outId = container.callManager.currentOpponentId ?? "Unknown"
                let outName = container.callManager.outgoingOpponentName ?? "Unknown"
                let outAvatar = container.callManager.outgoingOpponentAvatarUrl ?? ""
                CallView(opponentId: outId, opponentName: outName, opponentAvatarUrl: outAvatar)
            }
        }
    }
}
