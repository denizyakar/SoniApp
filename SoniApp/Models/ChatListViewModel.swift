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
    
    private var modelContext: ModelContext?
    
    init() {
        print("ChatListViewModel initialized")
        fetchUsers()
        
        SocketChatService.shared.onNewUserRegistered = { [weak self] in
            print("ViewModel: Received new register signal, refreshing list...")
            
            DispatchQueue.main.async {
                self?.fetchUsers()
            }
        }
        
    }
    func setup(context: ModelContext) {
        self.modelContext = context
        fetchUsers()
    }
    
    func fetchUsers() {
        // Fetch users from the server(comes as struct)
        AuthManager.shared.fetchAllUsers { [weak self] users in
            guard let self = self, let users = users else { return }
            
            DispatchQueue.main.async {
                // Save the incoming data to database
                self.saveUsersToDB(users: users)
            }
        }
    }
    
    private func saveUsersToDB(users: [ChatUser]) {
        guard let context = modelContext else { return }
        
        for user in users {
            // Update if it already exists, create it otherwise (Upsert logic)
            // SwiftData overwrites the ID if it's the same thanks to @Attribute(.unique).
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
