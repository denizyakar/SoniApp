//
//  Message.swift
//  SoniApp
//

import Foundation

/// Network DTO for messages.
struct Message: Identifiable, Codable {
    let id: String
    let text: String
    let senderId: String
    let receiverId: String
    let date: String?
    let senderName: String?
    let isRead: Bool?
    let readAt: String?
    let imageUrl: String?
    let clientId: String?
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case text
        case senderId
        case receiverId
        case date
        case senderName
        case isRead
        case readAt
        case clientId
        case imageUrl
    }
}
