//
//  ChatListView.swift
//  SoniApp
//
//  DEĞİŞTİRİLDİ: Unread badge + isInChatList flag + notification ses + deeplink.
//

import SwiftUI
import SwiftData

/// Kullanıcı listesi ekranı.
struct ChatListView: View {
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var viewModel = ChatListViewModel()
    @Environment(\.scenePhase) private var scenePhase
    
    @Query private var users: [UserItem]
    @Environment(\.modelContext) private var context
    
    /// Programmatic navigation için — deeplink bunu kullanır
    @State private var navigationPath = NavigationPath()
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            List(users.filter { $0.id != container.sessionStore.currentUserId }) { user in
                
                let chatUserStruct = ChatUser(id: user.id, username: user.username)
                
                NavigationLink(value: chatUserStruct) {
                    HStack {
                        Image(systemName: user.avatarName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                            .padding(.trailing, 8)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading) {
                            Text(user.username)
                                .font(.headline)
                            
                            Text("Click to start chatting")
                                .font(.footnote)
                                .foregroundColor(Color(.systemGray))
                        }
                        
                        Spacer()
                        
                        // Unread badge — kırmızı nokta + sayı
                        if let count = container.sessionStore.unreadCounts[user.id], count > 0 {
                            Text("\(count)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(minWidth: 20, minHeight: 20)
                                .background(Color.red)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Messages")
            .navigationDestination(for: ChatUser.self) { chatUser in
                ChatView(user: chatUser)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Logout") {
                        container.makeAuthService().logout()
                    }
                    .foregroundColor(.red)
                }
            }
            .onAppear {
                // ChatListView açıldığını bildir (push bastırmak için)
                container.sessionStore.isInChatList = true
                
                viewModel.setup(
                    context: context,
                    authService: container.makeAuthService(),
                    chatService: container.chatService,
                    sessionStore: container.sessionStore
                )
                
                // App kapalıyken push'a tıklandıysa → UserDefaults'ta deeplink var mı?
                checkPendingDeepLink()
            }
            .onDisappear {
                container.sessionStore.isInChatList = false
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .background || newPhase == .inactive {
                    container.sessionStore.isInChatList = false
                } else if newPhase == .active {
                    container.sessionStore.isInChatList = true
                    // scenePhase'te deeplink kontrolü YAPMA — onAppear zaten yapıyor
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pushNotificationTapped)) { notification in
                // App açıkken push'a tıklandı — UserDefaults'u temizle ki checkPending tekrar tetiklemesin
                UserDefaults.standard.removeObject(forKey: "deepLinkUserId")
                if let senderId = notification.userInfo?["senderId"] as? String {
                    navigateToChat(userId: senderId)
                }
            }
        }
    }
    
    // MARK: - Deeplink Navigation
    
    /// UserDefaults'ta bekleyen deeplink var mı kontrol et (sadece cold launch için)
    private func checkPendingDeepLink() {
        if let pendingId = UserDefaults.standard.string(forKey: "deepLinkUserId") {
            // Kullanıldı, temizle
            UserDefaults.standard.removeObject(forKey: "deepLinkUserId")
            
            // Kısa gecikme — view'ın tam yüklenmesini bekle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                navigateToChat(userId: pendingId)
            }
        }
    }
    
    /// Belirtilen userId'ye ait chat'e navigate et
    private func navigateToChat(userId: String) {
        // Zaten navigate ediyorsak tekrar etme
        guard navigationPath.isEmpty else { return }
        
        // Users listesinde bu kullanıcıyı bul
        if let userItem = users.first(where: { $0.id == userId }) {
            let chatUser = ChatUser(id: userItem.id, username: userItem.username)
            navigationPath.append(chatUser)
        }
    }
}
