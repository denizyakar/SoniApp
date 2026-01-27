import Foundation
import SwiftUI
import Combine

class AuthManager: ObservableObject {
    static let shared = AuthManager()
    @Published var isAuthenticated: Bool = false
    
    var currentUserId: String?
    var currentUsername: String?
    
    // Senin Tailscale IP'n
    private let baseURL = "https://soni-app.xyz"
    
    // ÖZEL SESSION: Proxy ayarlarını devre dışı bırakıyoruz!
    private var session: URLSession {
        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [:] // Boş sözlük = Proxy Yok!
        config.timeoutIntervalForRequest = 30.0
        return URLSession(configuration: config)
    }
    
    init() {
        if let token = UserDefaults.standard.string(forKey: "authToken") {
            print("💾 Kayıtlı token bulundu: \(token), Otomatik giriş yapılıyor.")
            
            self.currentUserId = UserDefaults.standard.string(forKey: "userId")
            self.currentUsername = UserDefaults.standard.string(forKey: "username")
            
            self.isAuthenticated = true
        }
    }
    
    // --- LOGIN ---
    func login(username: String, pass: String, completion: @escaping (Bool, String?) -> Void) {
        let url = URL(string: "\(baseURL)/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["username": username, "password": pass]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        // URLSession.shared yerine yukarıda tanımladığımız 'session'ı kullanıyoruz
        session.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("Hata Detayı: \(error?.localizedDescription ?? "Bilinmiyor")")
                completion(false, "Bağlantı hatası: \(error?.localizedDescription ?? "")")
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let token = json["token"] as? String {
                    self.saveUser(token: token, userId: json["userId"] as? String, username: json["username"] as? String)
                    completion(true, nil)
                } else {
                    let message = json["message"] as? String ?? "Bilinmeyen hata"
                    completion(false, message)
                }
            }
        }.resume()
    }
    
    // --- REGISTER ---
    func register(username: String, pass: String, completion: @escaping (Bool, String?) -> Void) {
        let url = URL(string: "\(baseURL)/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["username": username, "password": pass]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        // URLSession.shared yerine 'session' kullanıyoruz
        session.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("Hata Detayı: \(error?.localizedDescription ?? "Bilinmiyor")")
                completion(false, "Bağlantı hatası: \(error?.localizedDescription ?? "")")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 {
                completion(true, "Kayıt başarılı! Şimdi giriş yapabilirsin.")
            } else {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let message = json["message"] as? String ?? "Kayıt yapılamadı"
                    completion(false, message)
                } else {
                    completion(false, "Sunucu hatası")
                }
            }
        }.resume()
    }
    
    // --- LOGOUT ve SAVE USER aynı kalıyor ---
    func logout() {
        UserDefaults.standard.removeObject(forKey: "authToken")
        UserDefaults.standard.removeObject(forKey: "userId")   // <-- EKLE
        UserDefaults.standard.removeObject(forKey: "username") // <-- EKLE
                
        self.isAuthenticated = false
        self.currentUserId = nil
        self.currentUsername = nil
    }
    
    private func saveUser(token: String, userId: String?, username: String?) {
        UserDefaults.standard.set(token, forKey: "authToken")
        
        // --- YENİ EKLENEN KISIM ---
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
        }
    }
    
    // --- KULLANICILARI ÇEK (FETCH USERS) ---
        func fetchAllUsers(completion: @escaping ([ChatUser]?) -> Void) {
            let url = URL(string: "\(baseURL)/users")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            
            // Proxy ayarlı session'ımızı kullanıyoruz
            session.dataTask(with: request) { data, response, error in
                guard let data = data, error == nil else {
                    print("Kullanıcı çekme hatası: \(error?.localizedDescription ?? "")")
                    completion(nil)
                    return
                }
                
                do {
                    let users = try JSONDecoder().decode([ChatUser].self, from: data)
                    // Kendimizi listeden çıkaralım (Opsiyonel)
                    let filteredUsers = users.filter { $0.username != self.currentUsername }
                    completion(filteredUsers)
                } catch {
                    print("JSON Parse Hatası: \(error)")
                    completion(nil)
                }
            }.resume()
        }
    
}
