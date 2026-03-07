//
//  ChatListViewModel.swift
//  SoniApp

import Foundation
import SwiftUI
import SwiftData
import Combine
import AudioToolbox

@MainActor
class ChatListViewModel: ObservableObject {
    
    // MARK: - Dependencies
    private var userRepository: UserRepository?
    private var authService: AuthService?
    private var sessionStore: SessionStore?
    
    private var cancellables = Set<AnyCancellable>()
    private var isSetUp = false
    
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
        guard !isSetUp else { return }
        isSetUp = true
        
        print("🚀 ChatListViewModel: setup started")
        
        self.userRepository = UserRepository(modelContext: context)
        self.authService = authService
        self.sessionStore = sessionStore
        syncContacts()
        
        chatService.userRegisteredPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                // No longer auto-refresh — new users must be added manually via AddUserView
                // self?.syncContacts()
            }
            .store(in: &cancellables)
        
        chatService.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.handleIncomingMessage(message)
            }
            .store(in: &cancellables)
        
        chatService.profileUpdatedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (userId, nickname, avatarName, avatarUrl) in
                self?.handleProfileUpdate(userId: userId, nickname: nickname, avatarName: avatarName, avatarUrl: avatarUrl)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Incoming Message
    
    private func handleIncomingMessage(_ message: Message) {
        guard let sessionStore = sessionStore,
              message.senderId != sessionStore.currentUserId else { return }
        
        // Skip if this chat is currently open
        if sessionStore.currentChatPartnerId == message.senderId {
            return
        }
        
        sessionStore.incrementUnread(for: message.senderId)
        
        // Auto-add sender to contacts if not already in the list
        if !users.contains(where: { $0.id == message.senderId }) {
            // Server already auto-added via $addToSet in chat_message handler
            // Just refresh the local list to pick up the new contact
            syncContacts()
        }
        
        // Play sound only when ChatListView is visible
        if sessionStore.isInChatList {
            AudioServicesPlaySystemSound(1007)
        }
    }
    
    // MARK: - Profile Update
    
    private func handleProfileUpdate(userId: String, nickname: String, avatarName: String, avatarUrl: String) {
        do {
            // SwiftData update
            try userRepository?.updateUserProfile(userId: userId, nickname: nickname, avatarName: avatarName, avatarUrl: avatarUrl)
            
            // UI update
            if let index = users.firstIndex(where: { $0.id == userId }) {
                let currentUser = users[index]
                let newUser = ChatUser(
                    id: currentUser.id,
                    username: currentUser.username,
                    nickname: nickname,
                    avatarName: avatarName,
                    avatarUrl: avatarUrl,
                    unreadCount: currentUser.unreadCount
                )
                users[index] = newUser
            }
            
            print("✅ Profile updated for \(userId): nickname=\(nickname), avatar=\(avatarName), url=\(avatarUrl)")
        } catch {
            print("❌ Profile update error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Contacts Management
    
    func refreshUsers() {
        syncContacts()
    }
    
    func removeContact(userId: String) {
        guard let authService = authService else { return }
        
        // Remove from UI immediately
        users.removeAll { $0.id == userId }
        sessionStore?.unreadCounts.removeValue(forKey: userId)
        
        // Remove from SwiftData
        do {
            try userRepository?.removeContactLocally(userId: userId)
        } catch {
            print("❌ SwiftData remove error: \(error.localizedDescription)")
        }
        
        // Remove from server
        authService.removeContact(contactId: userId) { result in
            switch result {
            case .success:
                print("✅ Contact removed from server: \(userId)")
            case .failure(let error):
                print("❌ Server remove error: \(error.localizedDescription)")
            }
        }
    }
    
    func addContact(contactId: String, completion: @escaping (Bool) -> Void) {
        guard let authService = authService else {
            completion(false)
            return
        }
        
        authService.addContact(contactId: contactId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let chatUser):
                    // Add to UI if not already there
                    if !(self?.users.contains(where: { $0.id == chatUser.id }) ?? true) {
                        self?.users.append(chatUser)
                    }
                    // Add to SwiftData
                    do {
                        try self?.userRepository?.addContactLocally(user: chatUser)
                    } catch {
                        print("❌ SwiftData add error: \(error.localizedDescription)")
                    }
                    print("✅ Contact added: \(chatUser.username)")
                    completion(true)
                case .failure(let error):
                    print("❌ Add contact error: \(error.localizedDescription)")
                    completion(false)
                }
            }
        }
    }
    
    private func syncContacts() {
        guard let authService = authService,
              let sessionStore = sessionStore else { return }
        
        Task {
            do {
                let fetchedContacts = try await userRepository?.syncContactsFromServer(authService: authService, sessionStore: sessionStore)
                
                if let fetchedContacts = fetchedContacts {
                    self.users = fetchedContacts
                }
                
            } catch {
                print("❌ Contacts sync error: \(error.localizedDescription)")
            }
        }
    }
}
