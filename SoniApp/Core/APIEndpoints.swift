//
//  APIEndpoints.swift
//  SoniApp
//
//  Central place for all API endpoint definitions.
//  Eliminates magic strings scattered across multiple files.
//

import Foundation

/// Tüm backend endpoint'lerini tek bir yerde toplar.
///
/// **Neden var?**
/// Önceden `"https://soni-app.xyz"` string'i 4 farklı dosyada tekrarlanıyordu:
/// - AuthManager.swift
/// - ChatViewModel.swift
/// - TokenService.swift (3 kez!)
///
/// Eğer domain değişirse (ör. staging ortamı, yeni domain)
/// 4 dosyada 6 yeri bulup değiştirmen gerekirdi.
/// Şimdi sadece `baseURL`'i değiştirmen yeterli.
enum APIEndpoints {
    
    static let baseURL = "your_url"
    
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
    
    // MARK: - Messages
    static func messages(from senderId: String, to receiverId: String) -> URL {
        URL(string: "\(baseURL)/messages?from=\(senderId)&to=\(receiverId)")!
    }
    
    // MARK: - Push Notification Token
    static var updateToken: URL {
        URL(string: "\(baseURL)/update-token")!
    }
    
    static var removeToken: URL {
        URL(string: "\(baseURL)/remove-token")!
    }
}
