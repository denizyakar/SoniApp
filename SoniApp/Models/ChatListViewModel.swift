//
//  ChatListViewModel.swift
//  SoniApp
//
//  Created by Ali Deniz Yakar on 25.01.2026.
//

import Foundation
import SwiftUI
import SwiftData
import Combine

class ChatListViewModel: ObservableObject {
    // Artık @Published var users tutmuyoruz, çünkü View direkt veritabanına bakacak.
    
    private var modelContext: ModelContext?
    
    func setup(context: ModelContext) {
        self.modelContext = context
        fetchUsers()
    }
    
    func fetchUsers() {
        // 1. Sunucudan veriyi çek (Struct olarak gelir)
        AuthManager.shared.fetchAllUsers { [weak self] users in
            guard let self = self, let users = users else { return }
            
            DispatchQueue.main.async {
                // 2. Gelen veriyi Veritabanına Yaz
                self.saveUsersToDB(users: users)
            }
        }
    }
    
    private func saveUsersToDB(users: [ChatUser]) {
        guard let context = modelContext else { return }
        
        for user in users {
            // Eğer zaten varsa güncelle, yoksa oluştur (Upsert mantığı)
            // SwiftData @Attribute(.unique) sayesinde ID aynıysa üzerine yazar.
            let newUserItem = UserItem(
                id: user.id,
                username: user.username,
                avatarName: user.avatarName
            )
            context.insert(newUserItem)
        }
        
        try? context.save()
    }
}
