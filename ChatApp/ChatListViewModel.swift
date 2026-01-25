//
//  ChatListViewModel.swift
//  ChatApp
//
//  Created by Ali Deniz Yakar on 25.01.2026.
//

import Foundation
import Combine

class ChatListViewModel: ObservableObject {
    // List of friends to display
    @Published var users: [ChatUser] = []
    
    init() {
        loadMockUsers()
    }
    
    private func loadMockUsers() {
        // Simulating fetching friends from a database
        self.users = [
            ChatUser(name: "Ahmet (Backend)", avatarName: "person.fill"),
            ChatUser(name: "Ayşe (Designer)", avatarName: "star.fill"),
            ChatUser(name: "Mehmet (Tester)", avatarName: "bolt.fill")
        ]
    }
}
