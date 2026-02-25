//
//  ChatListView.swift
//  SoniApp

import SwiftUI
import SwiftData

/// User list screen.
struct ChatListView: View {
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var viewModel = ChatListViewModel()
    @Environment(\.scenePhase) private var scenePhase
    
    // Using ViewModel data directly instead of SwiftData @Query
    // @Query private var users: [UserItem]
    @Environment(\.modelContext) private var context
    
    /// For programmatic navigation — deeplink uses this
    @State private var navigationPath = NavigationPath()
    @State private var showingProfile = false
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            List(viewModel.filteredUsers) { user in
                
                let chatUserStruct = user
                
                NavigationLink(value: chatUserStruct) {
                    HStack {
                        AvatarView(chatUser: chatUserStruct, size: 48)
                            .padding(.trailing, 8)
                        
                        VStack(alignment: .leading) {
                            Text(user.displayName)
                                .font(.headline)
                                .foregroundColor(AppTheme.white)
                            
                            
                            Text("Click to start chatting")
                                .font(.footnote)
                                .foregroundColor(AppTheme.white)
                            
                        }
                        
                        Spacer()
                        
                        // Unread badge
                        if let count = container.sessionStore.unreadCounts[user.id], count > 0 {
                            Text("\(count)")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(AppTheme.primary)
                                .frame(minWidth: 30, minHeight: 30)
                                .background(.white)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(AppTheme.backgroundLight)
                .listRowSeparatorTint(AppTheme.white.opacity(0.1))
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Messages")
            
            .navigationDestination(for: ChatUser.self) { chatUser in
                ChatView(user: chatUser)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Logout") {
                        container.makeAuthService().logout()
                    }
                    .foregroundColor(AppTheme.white.opacity(0.9))
                    .bold()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingProfile = true
                    } label: {
                        AvatarView(
                            imageUrl: container.sessionStore.currentAvatarImageUrl,
                            sfSymbol: container.sessionStore.currentAvatarName ?? "person.circle",
                            size: 28
                        )
                    }
                }
            }
            .sheet(isPresented: $showingProfile) {
                UserProfileView()
                    .environmentObject(container)
            }
            .onAppear {
                // Notify that ChatListView is visible (for push suppression)
                container.sessionStore.isInChatList = true
                
                viewModel.setup(
                    context: context,
                    authService: container.makeAuthService(),
                    chatService: container.chatService,
                    sessionStore: container.sessionStore
                )
                
                // Init app-wide retry service (ModelContext available here)
                container.retryService.setup(modelContext: context)
                
                // If push was tapped while app was closed → check UserDefaults deeplink
                checkPendingDeepLink()
            }
            .onDisappear {
                container.sessionStore.isInChatList = false
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background || newPhase == .inactive {
                    container.sessionStore.isInChatList = false
                } else if newPhase == .active {
                    container.sessionStore.isInChatList = true
                    // Retry pending messages on app foreground
                    container.retryService.retryAllPendingMessages()
                    
                    // Sync unread counts (auto-sync from background)
                    viewModel.refreshUsers()
                    
                    // Clear app icon badge when user opens the app
                    UNUserNotificationCenter.current().setBadgeCount(0)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pushNotificationTapped)) { notification in
                // Push tapped while app is open — clear UserDefaults to prevent re-trigger
                UserDefaults.standard.removeObject(forKey: "deepLinkUserId")
                if let senderId = notification.userInfo?["senderId"] as? String {
                    navigateToChat(userId: senderId)
                }
            }
        }
    }
    
    // MARK: - Deeplink Navigation
    
    /// Check for pending deeplink in UserDefaults (cold launch only)
    private func checkPendingDeepLink() {
        if let pendingId = UserDefaults.standard.string(forKey: "deepLinkUserId") {
            // Already used, clear it
            UserDefaults.standard.removeObject(forKey: "deepLinkUserId")
            
            // Short delay — wait for view to fully load
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                navigateToChat(userId: pendingId)
            }
        }
    }
    
    /// Navigate to the chat for the given userId
    private func navigateToChat(userId: String) {
        // Don't navigate again if already navigating
        guard navigationPath.isEmpty else { return }
        
        // Find user in the ViewModel's list
        if let chatUser = viewModel.users.first(where: { $0.id == userId }) {
            navigationPath.append(chatUser)
        }
    }
}

#Preview("Full") {
    ChatListView()
        .environmentObject(DependencyContainer())
        .modelContainer(for: MessageItem.self, inMemory: true)
}

#Preview("Mock Users") {
    let mockUsers: [ChatUser] = [
        ChatUser(id: "1", username: "kankiii", nickname: "Kankam", avatarName: "star.circle.fill", avatarUrl: nil),
        ChatUser(id: "2", username: "ayse", nickname: "Ayşe", avatarName: "heart.circle.fill", avatarUrl: nil),
        ChatUser(id: "3", username: "mehmet", nickname: nil, avatarName: "flame.circle", avatarUrl: nil),
        ChatUser(id: "4", username: "zeynep", nickname: "Zey", avatarName: "moon.circle.fill", avatarUrl: nil),
    ]
    
    NavigationStack {
        List(mockUsers) { user in
            HStack {
                AvatarView(chatUser: user, size: 48)
                    .padding(.trailing, 8)
                    .foregroundColor(AppTheme.secondaryText)
                
                VStack(alignment: .leading) {
                    Text(user.displayName)
                        .font(.headline)
                        .foregroundColor(AppTheme.white)
                    
                    Text("Click to start chatting")
                        .font(.footnote)
                        .foregroundColor(AppTheme.white)
                }
                
                Spacer()
                
                // Mock unread badge
                if user.id == "1" {
                    Text("3")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(AppTheme.primary)
                        .frame(minWidth: 30, minHeight: 30)
                        .background(.white)
                        .clipShape(Circle())
                }
            }
            .padding(.vertical, 8)
            .listRowBackground(AppTheme.backgroundLight)
            .listRowSeparatorTint(AppTheme.white.opacity(0.1))
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Messages")
    }
}
