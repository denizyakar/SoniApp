//
//  APIEndpoints.swift
//  SoniApp
//
//  Central place for all API endpoint definitions.
//  Eliminates magic strings scattered across multiple files.
//

import Foundation

enum APIEndpoints {
    
    static let baseURL = "https://soni-app.xyz"
    
    // MARK: - Auth
    static var login: URL {
        URL(string: "\(baseURL)/login")!
    }
    
    static var register: URL {
        URL(string: "\(baseURL)/register")!
    }
    
    // MARK: - Users
    static var users: URL {
        URL(string: "\(baseURL)/users")!
    }
    
    static func updateProfile(userId: String) -> URL {
        URL(string: "\(baseURL)/users/\(userId)/profile")!
    }
    
    // MARK: - Messages
    static func messages(from senderId: String, to receiverId: String) -> URL {
        URL(string: "\(baseURL)/messages?from=\(senderId)&to=\(receiverId)")!
    }
    
    // MARK: - Push Notification Token
    static var updateToken: URL {
        URL(string: "\(baseURL)/update-token")!
    }
    
    static var updateVoipToken: URL {
        URL(string: "\(baseURL)/update-voip-token")!
    }
    
    static var removeToken: URL {
        URL(string: "\(baseURL)/remove-token")!
    }
    
    static var removeVoipToken: URL {
        URL(string: "\(baseURL)/remove-voip-token")!
    }
}
