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
    
    // MARK: - Setup
    
    func setup(context: ModelContext, authService: AuthService, chatService: SocketChatService, sessionStore: SessionStore) {
        // onAppear her çağrıldığında tekrar subscribe olmayı önle
        guard !isSetUp else { return }
        isSetUp = true
        
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
    
    // MARK: - Sync Users
    
    private func syncUsers() {
        guard let authService = authService else { return }
        
        Task {
            do {
                try await userRepository?.syncUsersFromServer(authService: authService)
            } catch {
                print("❌ User sync error: \(error.localizedDescription)")
            }
        }
    }
}
