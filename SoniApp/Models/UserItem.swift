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
    
    init(id: String, username: String, avatarName: String = "person.circle") {
        self.id = id
        self.username = username
        self.avatarName = avatarName
    }
}
