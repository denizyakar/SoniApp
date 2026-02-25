//
//  VoIPPushService.swift
//  SoniApp
//

import Foundation
import PushKit
import SwiftUI

protocol VoIPPushServiceProtocol: AnyObject {
    func registerForVoIP()
    func saveVoIPToken(username: String, token: String, completion: @escaping (Bool) -> Void)
    func removeVoIPToken(username: String)
    var onIncomingPush: (([String: Any], @escaping () -> Void) -> Void)? { get set }
}

final class VoIPPushService: NSObject, VoIPPushServiceProtocol, PKPushRegistryDelegate {
    
    private var voipRegistry: PKPushRegistry?
    var onIncomingPush: (([String: Any], @escaping () -> Void) -> Void)?
    
    func registerForVoIP() {
        DispatchQueue.main.async {
            self.voipRegistry = PKPushRegistry(queue: .main)
            self.voipRegistry?.delegate = self
            self.voipRegistry?.desiredPushTypes = [.voIP]
        }
    }
    
    func saveVoIPToken(username: String, token: String, completion: @escaping (Bool) -> Void) {
        let url = APIEndpoints.updateVoipToken
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "username": username,
            "voipToken": token
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ VoIP token save error: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("✅ VoIP token saved to server")
                completion(true)
            } else {
                print("⚠️ VoIP token save failed")
                completion(false)
            }
        }.resume()
    }
    
    func removeVoIPToken(username: String) {
        let url = APIEndpoints.removeVoipToken
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["username": username]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ VoIP token remove error: \(error.localizedDescription)")
                return
            }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("✅ VoIP token removed from server")
            }
        }.resume()
    }
    
    // MARK: - PKPushRegistryDelegate
    
    func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        
        let tokenString = credentials.token.map { String(format: "%02.2hhx", $0) }.joined()
        print("[VoIPPushService] VoIP Token: \(tokenString)")
        UserDefaults.standard.set(tokenString, forKey: "voipToken")
        
        if let username = UserDefaults.standard.string(forKey: "username") {
            saveVoIPToken(username: username, token: tokenString) { _ in }
        }
    }
    
    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        print("[VoIPPushService] PushKit token invalidated.")
    }
    
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        print("[VoIPPushService] Received Incoming VoIP Push: \(payload.dictionaryPayload)")
        
        if let onIncomingPush = onIncomingPush {
            let stringPayload = payload.dictionaryPayload as? [String: Any] ?? [:]
            onIncomingPush(stringPayload, completion)
        } else {
            completion()
        }
    }
}
