//
//  UserRepository.swift
//  SoniApp
//
//  Kullanıcı verisi koordinasyonu: Network → SwiftData.
//  Eskiden bu mantık ChatListViewModel + AuthManager içinde dağınıktı.
//

import Foundation
import SwiftData

// MARK: - Protocol

/// Kullanıcı veri operasyonlarının sözleşmesi.
protocol UserRepositoryProtocol {
    @discardableResult
    func syncUsersFromServer(authService: AuthService, sessionStore: SessionStoreProtocol) async throws -> [ChatUser]
}

// MARK: - Implementation

/// SwiftData tabanlı kullanıcı repository'si.
///
/// **Eskiden ne oluyordu?**
/// 1. `ChatListViewModel.fetchUsers()` → `AuthManager.shared.fetchAllUsers()`
/// 2. `AuthManager` kullanıcıları çekip callback ile geri dönüyordu
/// 3. ViewModel callback'te `saveUsersToDB()` çağırıyordu
///
/// **Şimdi ne oluyor?**
/// `UserRepository` tek başına hem çekme hem kaydetme işini hallediyor.
/// ViewModel sadece `try await repository.syncUsersFromServer()` diyor.
@MainActor
final class UserRepository: UserRepositoryProtocol {
    
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Sunucudan tüm kullanıcıları çeker, lokal DB'ye kaydeder ve unread count'ları günceller.
    @discardableResult
    func syncUsersFromServer(authService: AuthService, sessionStore: SessionStoreProtocol) async throws -> [ChatUser] {
        // Callback-based API'yi async/await'e çeviriyoruz (bridge)
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
            
            // YENİ: Backend'den gelen okunmamış mesaj sayısını SessionStore'a yaz
            if let unreadCount = user.unreadCount {
                sessionStore.unreadCounts[user.id] = unreadCount
            }
        }
        
        try modelContext.save()
        
        return users
    }
    
    /// Kullanıcı profilini güncelle (real-time socket event'ten)
    func updateUserProfile(userId: String, nickname: String, avatarName: String, avatarUrl: String = "") throws {
        let predicate = #Predicate<UserItem> { item in
            item.id == userId
        }
        
        let items = try modelContext.fetch(FetchDescriptor(predicate: predicate))
        if let userItem = items.first {
            userItem.nickname = nickname
            userItem.avatarName = avatarName
            if !avatarUrl.isEmpty {
                // Cache-buster: URL değişmiş gibi göstermek için timestamp ekle
                // Böylece AsyncImage eski fotoğrafı kullanmaz, yenisini indirir.
                let separator = avatarUrl.contains("?") ? "&" : "?"
                let timestamp = Date().timeIntervalSince1970
                userItem.avatarUrl = "\(avatarUrl)\(separator)t=\(timestamp)"
            }
            try modelContext.save()
        }
    }
}
