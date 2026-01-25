//
//  Message.swift
//  ChatApp
//
//  Created by Ali Deniz Yakar on 24.01.2026.
//

import Foundation

struct Message: Identifiable {
    let id : UUID
    let text: String
    let isFromCurrentUser: Bool
    let date: Date
}
