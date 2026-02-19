//
//  SessionStore.swift
//  SoniApp
//
//  Kullanıcı oturum bilgilerini (token, userId, username) yöneten izole store.
//  Daha önce bunların hepsi AuthManager içindeydi.
//

import Foundation
import Combine

// MARK: - Protocol

/// Oturum bilgilerine erişim sözleşmesi.
///
/// **Neden protocol?**
/// Unit test'te gerçek UserDefaults'a dokunmadan mock bir SessionStore
/// inject edebilmek için. Ayrıca ileride Keychain'e geçmek istersen
/// sadece yeni bir implementasyon yazarsın — hiçbir ViewModel değişmez.
protocol SessionStoreProtocol: AnyObject {
    var isAuthenticated: Bool { get }
    var currentUserId: String? { get }
    var currentUsername: String? { get }
    
    // YENİ: Profil Bilgileri (AuthService'in set edebilmesi için { get set })
    var currentNickname: String? { get set }
    var currentAvatarName: String? { get set }
    var currentAvatarUrl: String? { get set }
    
    var authToken: String? { get }
    var deviceToken: String? { get set }
    var currentChatPartnerId: String? { get set }
    var isInChatList: Bool { get set }
    
    /// Oturum bilgilerini kaydeder (login sonrası çağrılır)
    func saveSession(token: String, userId: String?, username: String?)
    
    /// Oturum bilgilerini temizler (logout sonrası çağrılır)
    func clearSession()
    
    /// Auth durumunu dinlemek için publisher
    var isAuthenticatedPublisher: AnyPublisher<Bool, Never> { get }
    
    /// Her kullanıcı için okunmamış mesaj sayısı
    var unreadCounts: [String: Int] { get set }
}

// MARK: - Implementation

/// UserDefaults tabanlı oturum bilgisi yöneticisi.
///
/// **Neden ayrı bir sınıf?**
/// Eskiden `AuthManager` şunların hepsini yapıyordu:
/// 1. Login/Register (network call)
/// 2. Token saklama (UserDefaults)
/// 3. User state tutma (currentUserId, username)
/// 4. Push notification token yönetimi
/// 5. Tüm kullanıcıları çekme (fetchAllUsers)
/// 6. Aktif chat partner state'i
///
/// Bu, SRP (Single Responsibility Principle) ihlaliydi.
/// `SessionStore` artık SADECE #2, #3 ve #6'dan sorumlu.
/// Her sınıfın tek bir değişme nedeni olmalı.
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
    
    /// UI bu değeri observe ediyor (SoniAppApp.swift'te auth kontrolü)
    @Published private(set) var isAuthenticated: Bool = false
    
    private(set) var currentUserId: String?
    private(set) var currentUsername: String?
    
    /// Kullanıcının seçtiği nickname (profil ekranından)
    var currentNickname: String? {
        didSet { UserDefaults.standard.set(currentNickname, forKey: Keys.nickname) }
    }
    
    /// Kullanıcının seçtiği avatar (profil ekranından)
    var currentAvatarName: String? {
        didSet { UserDefaults.standard.set(currentAvatarName, forKey: Keys.avatarName) }
    }
    
    /// Kullanıcının yüklediği profil fotoğrafı URL'si
    var currentAvatarUrl: String? {
        didSet { UserDefaults.standard.set(currentAvatarUrl, forKey: Keys.avatarUrl) }
    }
    
    var authToken: String? {
        UserDefaults.standard.string(forKey: Keys.authToken)
    }
    
    /// Push notification device token (AppDelegate tarafından set edilir)
    var deviceToken: String? {
        didSet {
            // AppDelegate'in de okuyabilmesi için UserDefaults'a yaz
            UserDefaults.standard.set(deviceToken, forKey: "deviceToken")
        }
    }
    
    /// Şu anda açık olan chat'in partner ID'si.
    var currentChatPartnerId: String? {
        didSet {
            UserDefaults.standard.set(currentChatPartnerId, forKey: "currentChatPartnerId")
        }
    }
    
    /// ChatListView açık mı? Push notification filtreleme için.
    /// AppDelegate bunu UserDefaults üzerinden okur.
    var isInChatList: Bool = false {
        didSet {
            UserDefaults.standard.set(isInChatList, forKey: "isInChatList")
        }
    }
    
    /// Push notification'a tıklandığında açılacak chat'in userId'si.
    /// AppDelegate set eder → SoniAppApp observe edip navigate eder.
    @Published var deepLinkUserId: String? = nil
    
    /// Her kullanıcı için okunmamış mesaj sayısı. (userId → count)
    /// ChatListView'da kırmızı badge göstermek için kullanılır.
    /// UserDefaults'ta persist ediliyor — app restart'ta kaybolmaz.
    @Published var unreadCounts: [String: Int] = [:] {
        didSet {
            // Her değişiklikte UserDefaults'a kaydet
            UserDefaults.standard.set(unreadCounts, forKey: "unreadCounts")
        }
    }
    
    // MARK: - Publishers
    
    var isAuthenticatedPublisher: AnyPublisher<Bool, Never> {
        $isAuthenticated.eraseToAnyPublisher()
    }
    
    // MARK: - Unread Helpers
    
    /// Bir kullanıcıdan gelen okunmamış mesaj sayısını artır.
    func incrementUnread(for userId: String) {
        unreadCounts[userId, default: 0] += 1
    }
    
    /// Bir kullanıcının okunmamış mesaj sayısını sıfırla (chat açıldığında).
    func clearUnread(for userId: String) {
        unreadCounts[userId] = nil
    }
    
    // MARK: - Init
    
    init() {
        // Uygulama açılışında mevcut token'ı kontrol et
        if UserDefaults.standard.string(forKey: Keys.authToken) != nil {
            self.currentUserId = UserDefaults.standard.string(forKey: Keys.userId)
            self.currentUsername = UserDefaults.standard.string(forKey: Keys.username)
            self.isAuthenticated = true
        }
        
        // AppDelegate tarafından kaydedilmiş device token'ı yükle
        self.deviceToken = UserDefaults.standard.string(forKey: "deviceToken")
        
        // Kaydedilmiş unread count'ları yükle
        if let saved = UserDefaults.standard.dictionary(forKey: "unreadCounts") as? [String: Int] {
            self.unreadCounts = saved
        }
        
        // Profil bilgilerini yükle
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
