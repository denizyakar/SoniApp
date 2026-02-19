//
//  ChatListView.swift
//  SoniApp
//
//  DEĞİŞTİRİLDİ: Unread badge + isInChatList + deeplink + profile menü.
//

import SwiftUI
import SwiftData

/// Kullanıcı listesi ekranı.
struct ChatListView: View {
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var viewModel = ChatListViewModel()
    @Environment(\.scenePhase) private var scenePhase
    
    // SWIFT DATA İPTAL (Geçici olarak doğrudan ViewModel'den veri alıyoruz)
    // @Query private var users: [UserItem]
    @Environment(\.modelContext) private var context
    
    /// Programmatic navigation için — deeplink bunu kullanır
    @State private var navigationPath = NavigationPath()
    @State private var showingProfile = false
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            // viewModel.filteredUsers kullanıyoruz (Search ve filtreleme zaten ViewModel'de)
            List(viewModel.filteredUsers) { user in
                
                // ChatUser struct zaten elimizde, tekrar oluşturmaya gerek yok
                let chatUserStruct = user
                
                NavigationLink(value: chatUserStruct) {
                    HStack {
                        AvatarView(chatUser: chatUserStruct, size: 48)
                            .padding(.trailing, 8)
                        
                        VStack(alignment: .leading) {
                            Text(user.displayName)
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingProfile = true
                    } label: {
                        AvatarView(
                            imageUrl: URL(string: "\(APIEndpoints.baseURL)\(container.sessionStore.currentAvatarUrl ?? "")"),
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
                // ChatListView açıldığını bildir (push bastırmak için)
                container.sessionStore.isInChatList = true
                
                viewModel.setup(
                    context: context,
                    authService: container.makeAuthService(),
                    chatService: container.chatService,
                    sessionStore: container.sessionStore
                )
                
                // App-wide retry servisini başlat (ModelContext burada mevcut)
                container.retryService.setup(modelContext: context)
                
                // App kapalıyken push'a tıklandıysa → UserDefaults'ta deeplink var mı?
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
                    // App geri geldiğinde pending mesajları kontrol et
                    container.retryService.retryAllPendingMessages()
                    
                    // Unread Count'ları güncelle (Background'dan gelince otomatik sync)
                    viewModel.refreshUsers()
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
        
        // Users listesinde bu kullanıcıyı bul (ViewModel'den)
        if let chatUser = viewModel.users.first(where: { $0.id == userId }) {
            navigationPath.append(chatUser)
        }
    }
}
