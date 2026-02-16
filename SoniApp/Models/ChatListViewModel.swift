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
//

import Foundation
import SwiftUI
import SwiftData
import Combine

/// Kullanıcı listesi ekranını yöneten ViewModel.
@MainActor
class ChatListViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    private var userRepository: UserRepository?
    private var authService: AuthService?
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Setup
    
    func setup(context: ModelContext, authService: AuthService, chatService: SocketChatService) {
        self.userRepository = UserRepository(modelContext: context)
        self.authService = authService
        
        // İlk yükleme
        syncUsers()
        
        // Yeni kullanıcı kaydolduğunda listeyi güncelle
        chatService.userRegisteredPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.syncUsers()
            }
            .store(in: &cancellables)
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
