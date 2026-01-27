//
//  Message.swift
//  SoniApp
//
//  Created by Ali Deniz Yakar on 24.01.2026.
//

import Foundation

struct Message: Identifiable, Codable {
    let id: String
    let text: String
    let senderId: String
    let receiverId: String
    let date: String? // MongoDB date format in string
    
    // Whom message is it?(where will the bubble locate)
    var isFromCurrentUser: Bool {
        return senderId == AuthManager.shared.currentUserId
    }
    
    enum CodingKeys: String, CodingKey {
        case id = "_id" // MongoDB sends _id, we use id
        case text
        case senderId
        case receiverId
        case date
    }
}
