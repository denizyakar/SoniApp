//
//  TokenService.swift
//  SoniApp
//
//  Created by Ali Deniz Yakar on 4.02.2026.
//

import Foundation

class TokenService {
    static let shared = TokenService()
    
    // Server adress
    private let serverUrl = "your_url/update"
    
    func saveDeviceToken(username: String, token: String, completion: @escaping (Bool) -> Void) {
        // make sure the url is correct
        guard let url = URL(string: "your_url/update") else {
            print("❌ [DEBUG] URL Error: Couldn't create URL")
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "username": username,
            "token": token
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        print("🚀 [DEBUG] Sending request")
        print("    -> URL: \(url.absoluteString)")
        print("    -> Body: \(body)")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            // Check if there is a connection error
            if let error = error {
                print("❌ [DEBUG] Connection Error: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            // Server response
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 [DEBUG] Server response code: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    print("✅ [DEBUG] Success: Token saved to server.")
                    completion(true)
                } else {
                    print("⚠️ [DEBUG] Failure: Server didn't return 200")
                    // Server error message
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        print("   -> Server message: \(responseString)")
                    }
                    completion(false)
                }
            }
        }.resume()
    }
    
    func removeDeviceToken(username: String) {
        // Delete token request to backend
        guard let url = URL(string: "yourl_url/remove") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["username": username]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        // don't wait for response -> fire and forget
        URLSession.shared.dataTask(with: request) { _, _, _ in
            print("👋 Delete token request sent to server")
        }.resume()
    }
    
}
