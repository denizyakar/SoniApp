//
//  UserItem.swift
//  SoniApp
//
//  Created by Ali Deniz Yakar on 26.01.2026.
//

import Foundation
import SwiftData

@Model
class UserItem {
    @Attribute(.unique) var id: String
    var username: String
    var avatarName: String
    var nickname: String
    var avatarUrl: String
    
    /// Görüntülenecek isim: nickname varsa onu, yoksa username'i göster
    var displayName: String {
        nickname.isEmpty ? username : nickname
    }
    
    /// Profil fotoğrafı tam URL'si (varsa)
    var avatarImageUrl: URL? {
        guard !avatarUrl.isEmpty else { return nil }
        if avatarUrl.hasPrefix("http") { return URL(string: avatarUrl) }
        return URL(string: "\(APIEndpoints.baseURL)\(avatarUrl)")
    }
    
    init(id: String, username: String, avatarName: String = "person.circle", nickname: String = "", avatarUrl: String = "") {
        self.id = id
        self.username = username
        self.avatarName = avatarName
        self.nickname = nickname
        self.avatarUrl = avatarUrl
    }
}
