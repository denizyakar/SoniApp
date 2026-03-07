//
//  UserRepository.swift
//  SoniApp
//

import Foundation
import SwiftData

// MARK: - Protocol

protocol UserRepositoryProtocol {
    @discardableResult
    func syncContactsFromServer(authService: AuthService, sessionStore: SessionStoreProtocol) async throws -> [ChatUser]
}

// MARK: - Implementation

@MainActor
final class UserRepository: UserRepositoryProtocol {
    
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Sync only contacts (not all users) from the server
    @discardableResult
    func syncContactsFromServer(authService: AuthService, sessionStore: SessionStoreProtocol) async throws -> [ChatUser] {
        let contacts: [ChatUser] = try await withCheckedThrowingContinuation { continuation in
            authService.fetchContacts { result in
                switch result {
                case .success(let users):
                    continuation.resume(returning: users)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        
        // Get existing contacts in SwiftData
        let existingItems = try modelContext.fetch(FetchDescriptor<UserItem>())
        let serverContactIds = Set(contacts.map { $0.id })
        
        // Remove contacts from SwiftData that are no longer in server contacts
        for item in existingItems {
            if !serverContactIds.contains(item.id) {
                modelContext.delete(item)
            }
        }
        
        // Upsert contacts from server
        for user in contacts {
            let userItem = UserItem(
                id: user.id,
                username: user.username,
                avatarName: user.avatar,
                nickname: user.nickname ?? "",
                avatarUrl: user.avatarUrl ?? ""
            )
            modelContext.insert(userItem)
            
            // Update unread counts from server
            if let unreadCount = user.unreadCount {
                sessionStore.unreadCounts[user.id] = unreadCount
            }
        }
        
        try modelContext.save()
        
        return contacts
    }
    
    /// Add a single contact to SwiftData
    func addContactLocally(user: ChatUser) throws {
        let userItem = UserItem(
            id: user.id,
            username: user.username,
            avatarName: user.avatar,
            nickname: user.nickname ?? "",
            avatarUrl: user.avatarUrl ?? ""
        )
        modelContext.insert(userItem)
        try modelContext.save()
    }
    
    /// Remove a single contact from SwiftData (deletes UserItem and related messages)
    func removeContactLocally(userId: String) throws {
        let predicate = #Predicate<UserItem> { item in
            item.id == userId
        }
        let items = try modelContext.fetch(FetchDescriptor(predicate: predicate))
        for item in items {
            modelContext.delete(item)
        }
        
        // Also remove cached messages for this contact
        let msgPredicate = #Predicate<MessageItem> { msg in
            msg.senderId == userId || msg.receiverId == userId
        }
        let messages = try modelContext.fetch(FetchDescriptor(predicate: msgPredicate))
        for msg in messages {
            modelContext.delete(msg)
        }
        
        try modelContext.save()
    }
    
    func updateUserProfile(userId: String, nickname: String, avatarName: String, avatarUrl: String = "") throws {
        let predicate = #Predicate<UserItem> { item in
            item.id == userId
        }
        
        let items = try modelContext.fetch(FetchDescriptor(predicate: predicate))
        if let userItem = items.first {
            userItem.nickname = nickname
            userItem.avatarName = avatarName
            if !avatarUrl.isEmpty {
                // Cache-buster timestamp to force AsyncImage refresh
                let separator = avatarUrl.contains("?") ? "&" : "?"
                let timestamp = Date().timeIntervalSince1970
                userItem.avatarUrl = "\(avatarUrl)\(separator)t=\(timestamp)"
            }
            try modelContext.save()
        }
    }
}
