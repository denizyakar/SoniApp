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
    
    /// Görüntülenecek isim: nickname varsa onu, yoksa username'i göster
    var displayName: String {
        if let nick = nickname, !nick.isEmpty { return nick }
        return username
    }
    
    /// Avatar SF Symbol adı — yoksa varsayılan
    var avatar: String {
        if let name = avatarName, !name.isEmpty { return name }
        return "person.circle"
    }
    
    /// Profil fotoğrafı tam URL'si (varsa)
    var avatarImageUrl: URL? {
        guard let path = avatarUrl, !path.isEmpty else { return nil }
        // Eğer tam URL geldiyse (http...) direkt kullan, yoksa baseURL ekle
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
    
    // YENİ: Backend'den okunmamış mesaj sayısını çeken opsiyonel alan
    var unreadCount: Int?
}
