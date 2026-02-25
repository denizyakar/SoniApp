//
//  AuthService.swift
//  SoniApp
//

import Foundation

final class AuthService {
    
    private let sessionStore: SessionStoreProtocol
    private let pushService: PushNotificationServiceProtocol
    private let voipPushService: VoIPPushServiceProtocol
    
    /// Proxy-free URLSession for Turkey ISP compatibility
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 30.0
        return URLSession(configuration: config)
    }()
    
    // MARK: - Init
    init(sessionStore: SessionStoreProtocol, pushNotificationService: PushNotificationServiceProtocol, voipPushService: VoIPPushServiceProtocol) {
        self.sessionStore = sessionStore
        self.pushService = pushNotificationService
        self.voipPushService = voipPushService
    }
    
    // MARK: - Login
    
    func login(username: String, password: String, completion: @escaping (Result<Void, AppError>) -> Void) {
        var request = URLRequest(url: APIEndpoints.login)
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
            
            // DEBUG: Inspect server response
            if let responseStr = String(data: data, encoding: .utf8) {
                print("🔍 Login response (\(data.count) bytes): \(responseStr.prefix(500))")
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(.decodingError(underlying: NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"]))))
                return
            }
            
            if let token = json["token"] as? String {
                self.sessionStore.saveSession(
                    token: token,
                    userId: json["userId"] as? String,
                    username: json["username"] as? String
                )
                
                if let avatarName = json["avatarName"] as? String {
                    self.sessionStore.currentAvatarName = avatarName
                }
                if let avatarUrl = json["avatarUrl"] as? String {
                    self.sessionStore.currentAvatarUrl = avatarUrl
                }
                if let nickname = json["nickname"] as? String {
                    self.sessionStore.currentNickname = nickname
                }
                
                // Fetch profile if login response doesn't include avatar info
                if self.sessionStore.currentAvatarUrl == nil || self.sessionStore.currentAvatarUrl?.isEmpty == true {
                    self.fetchProfile()
                }
                
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
        if let username = sessionStore.currentUsername {
            pushService.removeDeviceToken(username: username)
            voipPushService.removeVoIPToken(username: username)
        }
        sessionStore.clearSession()
    }
    
    // MARK: - Fetch All Users
    
    func fetchAllUsers(completion: @escaping (Result<[ChatUser], AppError>) -> Void) {
        var request = URLRequest(url: APIEndpoints.users)
        request.httpMethod = "GET"
        
        if let token = sessionStore.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ fetchAllUsers Network Error: \(error.localizedDescription)")
                completion(.failure(.networkError(underlying: error)))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                if let data = data, let str = String(data: data, encoding: .utf8) {
                    print("❌ fetchAllUsers Error \(httpResponse.statusCode): \(str)")
                }
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
                print("❌ JSON Decode Error: \(error)")
                if let str = String(data: data, encoding: .utf8) {
                     print("❌ Raw JSON Payload that failed: \(str)")
                }
                completion(.failure(.decodingError(underlying: error)))
            }
        }.resume()
    }
    
    // MARK: - Private Helpers
    
    private func sendPushTokenIfNeeded() {
        // Read fresh from UserDefaults — AppDelegate may have written it after SessionStore init
        let token = UserDefaults.standard.string(forKey: "deviceToken") ?? sessionStore.deviceToken
        guard let token = token, !token.isEmpty,
              let username = sessionStore.currentUsername else {
            print("⚠️ sendPushTokenIfNeeded: token=\(sessionStore.deviceToken ?? "nil"), username=\(sessionStore.currentUsername ?? "nil")")
            return
        }
        
        pushService.saveDeviceToken(username: username, token: token) { success in
            if success {
                print("✅ Push token sent to backend after login")
            } else {
                print("❌ Failed to send push token after login")
            }
        }
    }
    
    /// Fetch user profile after login (when login response doesn't include avatar).
    private func fetchProfile() {
        guard let userId = sessionStore.currentUserId else { return }
        
        let url = APIEndpoints.updateProfile(userId: userId)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        if let token = sessionStore.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        session.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("⚠️ fetchProfile: Could not load profile")
                return
            }
            
            let userDict = json["user"] as? [String: Any] ?? json
            
            DispatchQueue.main.async {
                if let avatarUrl = userDict["avatarUrl"] as? String, !avatarUrl.isEmpty {
                    self.sessionStore.currentAvatarUrl = avatarUrl
                    print("✅ Profile loaded: avatarUrl=\(avatarUrl)")
                }
                if let avatarName = userDict["avatarName"] as? String, !avatarName.isEmpty {
                    self.sessionStore.currentAvatarName = avatarName
                }
                if let nickname = userDict["nickname"] as? String, !nickname.isEmpty {
                    self.sessionStore.currentNickname = nickname
                }
            }
        }.resume()
    }
}
