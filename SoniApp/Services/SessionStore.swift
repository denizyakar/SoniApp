//
//  SessionStore.swift
//  SoniApp
//

import Foundation
import Combine

// MARK: - Protocol

protocol SessionStoreProtocol: AnyObject {
    var isAuthenticated: Bool { get }
    var currentUserId: String? { get }
    var currentUsername: String? { get }
    var currentNickname: String? { get set }
    var currentAvatarName: String? { get set }
    var currentAvatarUrl: String? { get set }
    var authToken: String? { get }
    var deviceToken: String? { get set }
    var currentChatPartnerId: String? { get set }
    var isInChatList: Bool { get set }
    
    func saveSession(token: String, userId: String?, username: String?)
    func clearSession()
    var isAuthenticatedPublisher: AnyPublisher<Bool, Never> { get }
    var unreadCounts: [String: Int] { get set }
}

// MARK: - Implementation

final class SessionStore: SessionStoreProtocol, ObservableObject {
    
    // MARK: - Keys
    private enum Keys {
        static let authToken = "authToken"
        static let userId = "userId"
        static let username = "username"
        static let nickname = "nickname"
        static let avatarName = "avatarName"
        static let avatarUrl = "avatarUrl"
    }
    
    // MARK: - Published State
    @Published private(set) var isAuthenticated: Bool = false
    
    private(set) var currentUserId: String?
    private(set) var currentUsername: String?
    
    var currentDisplayName: String {
        if let nick = currentNickname, !nick.isEmpty { return nick }
        return currentUsername ?? "Unknown"
    }
    
    var currentNickname: String? {
        didSet { UserDefaults.standard.set(currentNickname, forKey: Keys.nickname) }
    }
    
    var currentAvatarName: String? {
        didSet { UserDefaults.standard.set(currentAvatarName, forKey: Keys.avatarName) }
    }
    
    var currentAvatarUrl: String? {
        didSet { UserDefaults.standard.set(currentAvatarUrl, forKey: Keys.avatarUrl) }
    }
    
    /// Full avatar image URL (nil if no photo uploaded)
    var currentAvatarImageUrl: URL? {
        guard let path = currentAvatarUrl, !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: "\(APIEndpoints.baseURL)\(path)")
    }
    
    var authToken: String? {
        UserDefaults.standard.string(forKey: Keys.authToken)
    }
    
    /// Push notification device token (set by AppDelegate)
    var deviceToken: String? {
        didSet {
            UserDefaults.standard.set(deviceToken, forKey: "deviceToken")
        }
    }
    
    var currentChatPartnerId: String? {
        didSet {
            UserDefaults.standard.set(currentChatPartnerId, forKey: "currentChatPartnerId")
        }
    }
    
    var isInChatList: Bool = false {
        didSet {
            UserDefaults.standard.set(isInChatList, forKey: "isInChatList")
        }
    }
    
    /// Deep link target userId (set by AppDelegate on push notification tap)
    @Published var deepLinkUserId: String? = nil
    
    /// Unread message counts per user (userId → count)
    @Published var unreadCounts: [String: Int] = [:] {
        didSet {
            UserDefaults.standard.set(unreadCounts, forKey: "unreadCounts")
        }
    }
    
    // MARK: - Publishers
    
    var isAuthenticatedPublisher: AnyPublisher<Bool, Never> {
        $isAuthenticated.eraseToAnyPublisher()
    }
    
    func incrementUnread(for userId: String) {
        unreadCounts[userId, default: 0] += 1
    }
    
    func clearUnread(for userId: String) {
        unreadCounts[userId] = nil
    }
    
    // MARK: - Init
    
    init() {
        if UserDefaults.standard.string(forKey: Keys.authToken) != nil {
            self.currentUserId = UserDefaults.standard.string(forKey: Keys.userId)
            self.currentUsername = UserDefaults.standard.string(forKey: Keys.username)
            self.isAuthenticated = true
        }
        
        self.deviceToken = UserDefaults.standard.string(forKey: "deviceToken")
        
        if let saved = UserDefaults.standard.dictionary(forKey: "unreadCounts") as? [String: Int] {
            self.unreadCounts = saved
        }
        
        self.currentNickname = UserDefaults.standard.string(forKey: Keys.nickname)
        self.currentAvatarName = UserDefaults.standard.string(forKey: Keys.avatarName)
        self.currentAvatarUrl = UserDefaults.standard.string(forKey: Keys.avatarUrl)
    }
    
    // MARK: - Methods
    
    func saveSession(token: String, userId: String?, username: String?) {
        UserDefaults.standard.set(token, forKey: Keys.authToken)
        
        if let userId = userId {
            UserDefaults.standard.set(userId, forKey: Keys.userId)
        }
        if let username = username {
            UserDefaults.standard.set(username, forKey: Keys.username)
        }
        
        self.currentUserId = userId
        self.currentUsername = username
        
        DispatchQueue.main.async { [weak self] in
            self?.isAuthenticated = true
        }
    }
    
    func clearSession() {
        UserDefaults.standard.removeObject(forKey: Keys.authToken)
        UserDefaults.standard.removeObject(forKey: Keys.userId)
        UserDefaults.standard.removeObject(forKey: Keys.username)
        UserDefaults.standard.removeObject(forKey: Keys.nickname)
        UserDefaults.standard.removeObject(forKey: Keys.avatarName)
        UserDefaults.standard.removeObject(forKey: Keys.avatarUrl)
        
        self.currentUserId = nil
        self.currentUsername = nil
        self.currentNickname = nil
        self.currentAvatarName = nil
        self.currentAvatarUrl = nil
        self.isAuthenticated = false
    }
}
