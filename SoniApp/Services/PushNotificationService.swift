//
//  PushNotificationService.swift
//  SoniApp
//
//  Push notification token yönetimini izole eden servis.
//  Eskiden bu logic AuthManager + TokenService arasında dağınıktı.
//

import Foundation

// MARK: - Protocol

/// Push notification token operasyonlarının sözleşmesi.
protocol PushNotificationServiceProtocol {
    func saveDeviceToken(username: String, token: String, completion: @escaping (Bool) -> Void)
    func removeDeviceToken(username: String)
}

// MARK: - Implementation

/// Backend'e push notification token gönderen/silen servis.
///
/// **Neden ayrıldı?**
/// Eskiden `TokenService.shared` vardı ama `AuthManager` de token
/// yönetimine karışıyordu (`setDeviceToken`, `sendTokenToBackend`).
/// Bu sınıf, token logic'ini tek bir yerde toplar.
///
/// **Neden `static let shared` kaldırıldı?**
/// Singleton'ı kaldırarak bu servisi DI ile inject ediyoruz.
/// Böylece unit test'te gerçek network çağrısı yapmadan
/// mock bir servis geçebiliriz.
final class PushNotificationService: PushNotificationServiceProtocol {
    
    func saveDeviceToken(username: String, token: String, completion: @escaping (Bool) -> Void) {
        let url = APIEndpoints.updateToken
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "username": username,
            "token": token
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Push token save error: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("✅ Push token saved to server")
                completion(true)
            } else {
                print("⚠️ Push token save failed")
                completion(false)
            }
        }.resume()
    }
    
    func removeDeviceToken(username: String) {
        let url = APIEndpoints.removeToken
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["username": username]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        // Fire-and-forget: bilerek response beklenmez
        URLSession.shared.dataTask(with: request) { _, _, _ in
            print("👋 Remove token request sent")
        }.resume()
    }
}
