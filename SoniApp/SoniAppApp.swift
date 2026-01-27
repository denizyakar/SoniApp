//
//  SoniAppApp.swift
//  SoniApp
//
//  Created by Ali Deniz Yakar on 24.01.2026.
//

import SwiftUI
import SwiftData

@main
struct ChatAppApp: App {
    @ObservedObject var authManager = AuthManager.shared
    
    init() {
            // Connection starts after app is running
            SocketChatService.shared.connect()
        }
    
    var body: some Scene {
            WindowGroup {
                // If logged in -> ChatListView
                if authManager.isAuthenticated {
                    ChatListView()
                }
                // If not -> AuthView
                else {
                    AuthView()
                }
            }
            .modelContainer(for: [MessageItem.self, UserItem.self])
        }
}
