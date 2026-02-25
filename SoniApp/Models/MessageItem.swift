//
//  MessageItem.swift
//  SoniApp
//

import Foundation
import SwiftData

/// SwiftData persistent entity for messages.
@Model
class MessageItem {
    @Attribute(.unique) var id: String
    var text: String
    var senderId: String
    var receiverId: String
    var date: Date
    var senderName: String
    var isRead: Bool
    var readAt: Date?
    var statusRaw: String
    var imageUrl: String?
    
    /// Type-safe status
    @Transient
    var status: MessageStatus {
        get { MessageStatus(rawValue: statusRaw) ?? .sent }
        set { statusRaw = newValue.rawValue }
    }
    
    init(id: String, text: String, senderId: String, receiverId: String, date: Date, senderName: String = "", isRead: Bool = false, readAt: Date? = nil, status: MessageStatus = .sent, imageUrl: String? = nil) {
        self.id = id
        self.text = text
        self.senderId = senderId
        self.receiverId = receiverId
        self.date = date
        self.senderName = senderName
        self.isRead = isRead
        self.readAt = readAt
        self.statusRaw = status.rawValue
        self.imageUrl = imageUrl
    }
    
    func isFromCurrentUser(userId: String?) -> Bool {
        return senderId == userId
    }
}
