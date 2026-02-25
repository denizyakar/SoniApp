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
        syncUsers()
        
        chatService.userRegisteredPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.syncUsers()
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
    
    func refreshUsers() {
        syncUsers()
    }
    
    private func syncUsers() {
        guard let authService = authService,
              let sessionStore = sessionStore else { return }
        
        Task {
            do {
                let fetchedUsers = try await userRepository?.syncUsersFromServer(authService: authService, sessionStore: sessionStore)
                
                if let fetchedUsers = fetchedUsers {
                    self.users = fetchedUsers
                }
                
            } catch {
                print("❌ User sync error: \(error.localizedDescription)")
            }
        }
    }
}
