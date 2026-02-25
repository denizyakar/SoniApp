//
//  ChatUser.swift
//  SoniApp
//
//  Created by Ali Deniz Yakar on 25.01.2026.
//

import Foundation

struct ChatUser: Identifiable, Codable, Hashable {
    let id: String
    let username: String
    let nickname: String?
    let avatarName: String?
    let avatarUrl: String?
    
    /// Display name: nickname if available, otherwise username
    var displayName: String {
        if let nick = nickname, !nick.isEmpty { return nick }
        return username
    }
    
    var avatar: String {
        if let name = avatarName, !name.isEmpty { return name }
        return "person.circle"
    }
    
    var avatarImageUrl: URL? {
        guard let path = avatarUrl, !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: "\(APIEndpoints.baseURL)\(path)")
    }
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case username
        case nickname
        case avatarName
        case avatarUrl
        case unreadCount
    }
    
    var unreadCount: Int?
}
