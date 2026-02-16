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
    func syncUsersFromServer(authService: AuthService) async throws
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
    
    /// Sunucudan tüm kullanıcıları çeker ve lokal DB'ye kaydeder.
    func syncUsersFromServer(authService: AuthService) async throws {
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
                avatarName: user.avatarName
            )
            modelContext.insert(userItem)
        }
        
        try modelContext.save()
    }
}
