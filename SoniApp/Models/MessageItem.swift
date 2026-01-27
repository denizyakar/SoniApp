//
//  MessageItem.swift
//  SoniApp
//
//  Created by Ali Deniz Yakar on 26.01.2026.
//

import Foundation
import SwiftData

@Model
class MessageItem {
    // @Attribute(.unique) ensures we don't save duplicate messages with the same ID
    @Attribute(.unique) var id: String
    var text: String
    var senderId: String
    var receiverId: String
    var date: Date
    
    // Helper property to check ownership (Not saved to DB, calculated on the fly)
    @Transient
    var isFromCurrentUser: Bool {
        return senderId == AuthManager.shared.currentUserId
    }
    
    init(id: String, text: String, senderId: String, receiverId: String, date: Date) {
        self.id = id
        self.text = text
        self.senderId = senderId
        self.receiverId = receiverId
        self.date = date
    }
}
