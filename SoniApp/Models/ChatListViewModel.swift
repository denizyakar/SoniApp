//
//  ChatListViewModel.swift
//  SoniApp
//
//  YENİDEN YAZILDI.
//
//  Değişiklikler:
//  1. SocketChatService.shared → Combine publisher ile dinleme
//  2. AuthManager.shared.fetchAllUsers → AuthService (inject)
//  3. ModelContext inline yönetimi → UserRepository
//  4. DispatchQueue.main.async kalabalığı → Combine .receive(on:)
//  5. YENİ: messagePublisher subscribe → unread count artır + ses çal
//

import Foundation
import SwiftUI
import SwiftData
import Combine
import AudioToolbox

/// Kullanıcı listesi ekranını yöneten ViewModel.
@MainActor
class ChatListViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    private var userRepository: UserRepository?
    private var authService: AuthService?
    private var sessionStore: SessionStore?
    
    private var cancellables = Set<AnyCancellable>()
    private var isSetUp = false  // ← Duplicate setup önleme
    
    // MARK: - Properties
    @Published var users: [ChatUser] = []
    @Published var searchText: String = ""
    
    var filteredUsers: [ChatUser] {
        if searchText.isEmpty {
            return users
        } else {
            return users.filter {
                $0.username.localizedCaseInsensitiveContains(searchText) ||
                ($0.nickname?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }
    
    // MARK: - Setup
    
    func setup(context: ModelContext, authService: AuthService, chatService: SocketChatService, sessionStore: SessionStore) {
        // onAppear her çağrıldığında tekrar subscribe olmayı önle
        guard !isSetUp else { return }
        isSetUp = true
        
        print("🚀 ChatListViewModel: setup started")
        
        self.userRepository = UserRepository(modelContext: context)
        self.authService = authService
        self.sessionStore = sessionStore
        
        // İlk yükleme
        syncUsers()
        
        // Yeni kullanıcı kaydolduğunda listeyi güncelle
        chatService.userRegisteredPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.syncUsers()
            }
            .store(in: &cancellables)
        
        // Gelen mesajları dinle → unread count artır + ses çal
        chatService.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.handleIncomingMessage(message)
            }
            .store(in: &cancellables)
        
        // Profil güncellemesi dinle → UserItem'ı güncelle
        chatService.profileUpdatedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (userId, nickname, avatarName, avatarUrl) in
                self?.handleProfileUpdate(userId: userId, nickname: nickname, avatarName: avatarName, avatarUrl: avatarUrl)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Incoming Message Handler
    
    /// ChatListView açıkken gelen mesaj:
    /// 1. Eğer o chat açık değilse → unread count artır
    /// 2. Sadece ChatListView'dayken in-app ses çal
    private func handleIncomingMessage(_ message: Message) {
        guard let sessionStore = sessionStore,
              message.senderId != sessionStore.currentUserId else { return }
        
        // O chat şu an açık mı?
        if sessionStore.currentChatPartnerId == message.senderId {
            return  // Chat açık, unread artırma
        }
        
        // Unread count artır (her durumda — chat'teyken de, list'teyken de)
        sessionStore.incrementUnread(for: message.senderId)
        
        // Ses sadece ChatListView'dayken çal — chat açıkken sessiz
        if sessionStore.isInChatList {
            AudioServicesPlaySystemSound(1007)
        }
    }
    
    // MARK: - Profile Update Handler
    
    /// Başka bir kullanıcı profilini güncellediğinde,
    /// lokal SwiftData'daki UserItem'ı güncelle ve self.users listesini yenile.
    private func handleProfileUpdate(userId: String, nickname: String, avatarName: String, avatarUrl: String) {
        do {
            // 1. SwiftData Güncelle (Kalıcılık için)
            try userRepository?.updateUserProfile(userId: userId, nickname: nickname, avatarName: avatarName, avatarUrl: avatarUrl)
            
            // 2. UI Güncelle (Anlık görüntüleme için)
            if let index = users.firstIndex(where: { $0.id == userId }) {
                // Struct olduğu için kopyasını oluşturup güncellememiz lazım
                var updatedUser = users[index]
                // ChatUser struct'ında bu alanlar let olabilir, o zaman struct'ı yeniden oluşturun
                let newUser = ChatUser(
                    id: updatedUser.id,
                    username: updatedUser.username,
                    nickname: nickname,
                    avatarName: avatarName,
                    avatarUrl: avatarUrl,
                    unreadCount: updatedUser.unreadCount
                )
                users[index] = newUser
            }
            
            print("✅ Profile updated for \(userId): nickname=\(nickname), avatar=\(avatarName), url=\(avatarUrl)")
        } catch {
            print("❌ Profile update error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Sync Users
    
    // Uygulama background'dan geldiğinde de çalışsın diye public yaptık
    func refreshUsers() {
        print("🔄 ChatListViewModel: refreshUsers (scenePhase active)")
        syncUsers()
    }
    
    private func syncUsers() {
        print("📨 ChatListViewModel: syncUsers called...")
        guard let authService = authService,
              let sessionStore = sessionStore else {
            print("⚠️ ChatListViewModel: Dependencies missing for syncUsers")
            return
        }
        
        Task {
            do {
                print("⏳ ChatListViewModel: Requesting syncUsersFromServer...")
                let fetchedUsers = try await userRepository?.syncUsersFromServer(authService: authService, sessionStore: sessionStore)
                
                // UI Güncelleme (Main Actor -> self.users)
                if let fetchedUsers = fetchedUsers {
                    self.users = fetchedUsers
                    print("✅ ChatListViewModel: Updated UI with \(fetchedUsers.count) users")
                }
                
                print("✅ ChatListViewModel: syncUsersFromServer DONE")
            } catch {
                print("❌ User sync error: \(error.localizedDescription)")
            }
        }
    }
}
