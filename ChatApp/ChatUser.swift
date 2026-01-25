//
//  ChatUser.swift
//  ChatApp
//
//  Created by Ali Deniz Yakar on 25.01.2026.
//

import Foundation

struct ChatUser: Identifiable {
    let id = UUID()
    let name: String
    let avatarName: String // Resmin adı (Assets'teki)
}
