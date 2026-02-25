//
//  UserRepository.swift
//  SoniApp
//

import Foundation
import SwiftData

// MARK: - Protocol

protocol UserRepositoryProtocol {
    @discardableResult
    func syncUsersFromServer(authService: AuthService, sessionStore: SessionStoreProtocol) async throws -> [ChatUser]
}

// MARK: - Implementation

@MainActor
final class UserRepository: UserRepositoryProtocol {
    
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    @discardableResult
    func syncUsersFromServer(authService: AuthService, sessionStore: SessionStoreProtocol) async throws -> [ChatUser] {
        let users: [ChatUser] = try await withCheckedThrowingContinuation { continuation in
            authService.fetchAllUsers { result in
                switch result {
                case .success(let users):
                    continuation.resume(returning: users)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        
        // Batch upsert
        for user in users {
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
        
        return users
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
