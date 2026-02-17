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
    var avatarName: String {
        return "person.circle"
    }
    
    enum CodingKeys: String, CodingKey {
        case id = "_id" // Match _id in MongoDB with id here
        case username
    }
}
