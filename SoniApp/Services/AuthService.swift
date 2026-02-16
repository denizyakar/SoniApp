//
//  AuthService.swift
//  SoniApp
//
//  Refactored from AuthManager: SADECE authentication operasyonları.
//  State yönetimi → SessionStore'a, token yönetimi → PushNotificationService'e taşındı.
//

import Foundation

/// Authentication servisi — login, register, logout ve user fetch.
///
/// **Eskiden AuthManager ne yapıyordu?**
/// 1. Login / Register (network call)          → ✅ BURADA KALDI
/// 2. Logout                                   → ✅ BURADA KALDI
/// 3. Tüm kullanıcıları çekme (fetchAllUsers)  → ✅ BURADA KALDI
/// 4. Token saklama (UserDefaults)              → ❌ SessionStore'a taşındı
/// 5. Push notification token                   → ❌ PushNotificationService'e taşındı
/// 6. User state (currentUserId, username)      → ❌ SessionStore'a taşındı
/// 7. currentChatPartnerId                      → ❌ SessionStore'a taşındı
/// 8. URLSession config                         → ❌ Burada kaldı (ama izole)
///
/// **Neden `static let shared` kaldırıldı?**
/// `AuthService` artık DependencyContainer tarafından yaratılıyor.
/// İhtiyaç duyan her sınıf, init parametresi olarak alıyor.
/// Bu sayede test'te mock geçebilirsin.
final class AuthService {
    
    // MARK: - Dependencies (inject edilen bağımlılıklar)
    
    private let sessionStore: SessionStoreProtocol
    private let pushService: PushNotificationServiceProtocol
    
    // MARK: - Network Config
    
    /// Proxy'siz URLSession — Türkiye'deki bazı ISP'ler proxy ekleyebiliyor.
    private var session: URLSession {
        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 30.0
        return URLSession(configuration: config)
    }
    
    // MARK: - Init
    
    init(sessionStore: SessionStoreProtocol, pushNotificationService: PushNotificationServiceProtocol) {
        self.sessionStore = sessionStore
        self.pushService = pushNotificationService
    }
    
    // MARK: - Login
    
    func login(username: String, password: String, completion: @escaping (Result<Void, AppError>) -> Void) {
        var request = URLRequest(url: APIEndpoints.login)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["username": username, "password": password]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        // ⚠️ [weak self] KULLANMIYORUZ — Neden?
        // AuthService, View'daki handleAction() içinde `let authService = container.makeAuthService()`
        // olarak yaratılıyor. Fonksiyon bitince bu lokal değişken ölür.
        // Eğer [weak self] kullansaydık, network callback döndüğünde self = nil olurdu
        // ve `guard let self = self else { return }` sessizce çıkardı.
        // Closure, self'i strong capture ederek AuthService'i callback gelene kadar canlı tutar.
        // Bu bilerek yapılmıştır — service objesi callback'ten sonra zaten işini tamamlar ve ölür.
        session.dataTask(with: request) { data, response, error in
            
            if let error = error {
                completion(.failure(.networkError(underlying: error)))
                return
            }
            
            guard let data = data else {
                completion(.failure(.serverError(message: "No data received")))
                return
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(.decodingError(underlying: NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"]))))
                return
            }
            
            if let token = json["token"] as? String {
                // Oturumu kaydet
                self.sessionStore.saveSession(
                    token: token,
                    userId: json["userId"] as? String,
                    username: json["username"] as? String
                )
                
                // Push notification token'ı gönder
                self.sendPushTokenIfNeeded()
                
                completion(.success(()))
            } else {
                let message = json["message"] as? String ?? "Unknown error"
                completion(.failure(.serverError(message: message)))
            }
        }.resume()
    }
    
    // MARK: - Register
    
    func register(username: String, password: String, completion: @escaping (Result<String, AppError>) -> Void) {
        var request = URLRequest(url: APIEndpoints.register)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["username": username, "password": password]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(underlying: error)))
                return
            }
            
            guard let data = data else {
                completion(.failure(.serverError(message: "No data received")))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 {
                completion(.success("Register successful! Now you can log in."))
            } else {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let message = json["message"] as? String ?? "Couldn't register."
                    completion(.failure(.serverError(message: message)))
                } else {
                    completion(.failure(.serverError(message: "Server error. Try again later.")))
                }
            }
        }.resume()
    }
    
    // MARK: - Logout
    
    func logout() {
        // Token'ı backend'den sil
        if let username = sessionStore.currentUsername {
            pushService.removeDeviceToken(username: username)
        }
        
        // Lokal oturumu temizle
        sessionStore.clearSession()
    }
    
    // MARK: - Fetch All Users
    
    func fetchAllUsers(completion: @escaping (Result<[ChatUser], AppError>) -> Void) {
        var request = URLRequest(url: APIEndpoints.users)
        request.httpMethod = "GET"
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(underlying: error)))
                return
            }
            
            guard let data = data else {
                completion(.failure(.serverError(message: "No data received")))
                return
            }
            
            do {
                let users = try JSONDecoder().decode([ChatUser].self, from: data)
                let filtered = users.filter { $0.id != self.sessionStore.currentUserId }
                completion(.success(filtered))
            } catch {
                completion(.failure(.decodingError(underlying: error)))
            }
        }.resume()
    }
    
    // MARK: - Private Helpers
    
    private func sendPushTokenIfNeeded() {
        guard let token = sessionStore.deviceToken,
              let username = sessionStore.currentUsername else { return }
        
        pushService.saveDeviceToken(username: username, token: token) { success in
            if success {
                print("✅ Push token sent to backend after login")
            }
        }
    }
}
