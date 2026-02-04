import Foundation
import SwiftUI
import Combine

class AuthManager: ObservableObject {
    static let shared = AuthManager()
    @Published var isAuthenticated: Bool = false
    var currentChatPartnerId: String? = nil
    var currentUserId: String?
    var currentUsername: String?
    //push notif token
    var deviceToken: String?
    
    // 2. Function called by AppDelegate
        func setDeviceToken(_ token: String) {
            self.deviceToken = token
            print("AuthManager: Token saved locally: \(token)")
            
            // If user is ALREADY logged in, send token immediately
            if isAuthenticated { 
                sendTokenToBackend()
            }
        }
    
    // 3. Helper function to call TokenService
    private func sendTokenToBackend() {
        guard let token = deviceToken, let username = self.currentUsername else { return }
            
            print("AuthManager: Token sending to backend...")
            
        TokenService.shared.saveDeviceToken(username: username, token: token) { success in
                if success {
                    print("✅ Token succesfully saved to server")
                } else {
                    print("⚠️ Token couldn't be saved to server")
                }
            }
        }
    
    // Domain IP
    private let baseURL = "your_url"
    
    // Disabling proxy settings
    private var session: URLSession {
        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [:] // Empty dict -> no proxy
        config.timeoutIntervalForRequest = 30.0
        return URLSession(configuration: config)
    }
    
    init() {
        if let token = UserDefaults.standard.string(forKey: "authToken") {
            print("Found existing token: \(token), Logging in automatically.")
            
            self.currentUserId = UserDefaults.standard.string(forKey: "userId")
            self.currentUsername = UserDefaults.standard.string(forKey: "username")
            
            self.isAuthenticated = true
        }
    }
    
    // Login
    func login(username: String, pass: String, completion: @escaping (Bool, String?) -> Void) {
        let url = URL(string: "\(baseURL)/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["username": username, "password": pass]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        // Instead of URLSession.shared, we use the 'session' we defined above
        session.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("Error info: \(error?.localizedDescription ?? "Unknown error")")
                completion(false, "Connection error: \(error?.localizedDescription ?? "")")
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let token = json["token"] as? String {
                    self.saveUser(token: token, userId: json["userId"] as? String, username: json["username"] as? String)
                    completion(true, nil)
                } else {
                    let message = json["message"] as? String ?? "Unknown error"
                    completion(false, message)
                }
            }
        }.resume()
    }
    
    // Register
    func register(username: String, pass: String, completion: @escaping (Bool, String?) -> Void) {
        let url = URL(string: "\(baseURL)/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["username": username, "password": pass]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        // Instead of URLSession.shared, we use the 'session' we defined above.
        session.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("Error info: \(error?.localizedDescription ?? "Unknown")")
                completion(false, "Connection error: \(error?.localizedDescription ?? "")")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 {
                completion(true, "Register succesful! Now you can log in.")
            } else {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let message = json["message"] as? String ?? "Couldn't register."
                    completion(false, message)
                } else {
                    completion(false, "Server error. Try again later.")
                }
            }
        }.resume()
    }
    
    // Logout and Save User stays same
    func logout() {
        
        // Delete the record in the server before logging out
        if let username = self.currentUsername {
                TokenService.shared.removeDeviceToken(username: username)
            }
        
        UserDefaults.standard.removeObject(forKey: "authToken")
        UserDefaults.standard.removeObject(forKey: "userId")
        UserDefaults.standard.removeObject(forKey: "username")
                
        self.isAuthenticated = false
        self.currentUserId = nil
        self.currentUsername = nil
        
    }
    
    private func saveUser(token: String, userId: String?, username: String?) {
        UserDefaults.standard.set(token, forKey: "authToken")
        
        if let userId = userId {
            UserDefaults.standard.set(userId, forKey: "userId")
        }
        if let username = username {
            UserDefaults.standard.set(username, forKey: "username")
        }
        
        self.currentUserId = userId
        self.currentUsername = username
        
        DispatchQueue.main.async {
            self.isAuthenticated = true
            
            self.sendTokenToBackend()
        }
    }
    
    // Fetching Users
        func fetchAllUsers(completion: @escaping ([ChatUser]?) -> Void) {
            let url = URL(string: "\(baseURL)/users")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            
            session.dataTask(with: request) { data, response, error in
                guard let data = data, error == nil else {
                    print("Fetching users error: \(error?.localizedDescription ?? "")")
                    completion(nil)
                    return
                }
                
                do {
                    let users = try JSONDecoder().decode([ChatUser].self, from: data)
                    // Not including current user in the list:
                    let filteredUsers = users.filter { $0.username != AuthManager.shared.currentUsername }
                    completion(filteredUsers)
                } catch {
                    print("JSON Parse Error: \(error)")
                    completion(nil)
                }
            }.resume()
        }
    
}
