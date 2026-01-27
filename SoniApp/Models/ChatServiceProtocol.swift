//
//  ChatService.swift
//  SoniApp
//
//  Created by Ali Deniz Yakar on 24.01.2026.
//

import Foundation
import SocketIO

// This is our "Contract". Any chat service MUST behave like this.
protocol ChatServiceProtocol {
    var onMessageReceived: ((Message) -> Void)? { get set }
    func connect()
    func sendMessage(text: String, receiverId: String) // Burayı da güncelledik
}

// A fake service for development and UI testing.
class SocketChatService: ChatServiceProtocol {
    // SINGLETON
    static let shared = SocketChatService()
    
    var onMessageReceived: ((Message) -> Void)?
    
    private var manager: SocketManager
    private var socket: SocketIOClient
    
    private init() {
        // IP Adresini kontrol et
        let url = URL(string: "https://soni-app.xyz")!
        
        manager = SocketManager(socketURL: url, config: [
            .log(true),
            .compress
        ])
        socket = manager.defaultSocket
        
        setupListeners()
    }
    
    func connect() {
        print("[SocketService] Bağlanılıyor...")
        socket.connect()
    }
    
    // NOT: Artık mesaj gönderme işini ChatViewModel yapıyor ama
    // protokol gereği burada tutuyoruz (veya ileride kullanırız diye güncelledik)
    func sendMessage(text: String, receiverId: String) {
        guard let myId = AuthManager.shared.currentUserId else { return }
        
        let data: [String: Any] = [
            "text": text,
            "senderId": myId,
            "receiverId": receiverId
        ]
        
        socket.emit("chat_message", data)
    }
    
    private func setupListeners() {
        // 1. Bağlantı Başarılı Olduğunda
        socket.on(clientEvent: .connect) { data, ack in
            print("[SocketService] BAĞLANDI! ✅")
        }
        
        // 2. Yeni Mesaj Geldiğinde (HATA VEREN KISIM DÜZELTİLDİ)
        socket.on("receive_message") { [weak self] data, ack in
            // Manuel parse etmek yerine Codable kullanıyoruz
            guard let dataArray = data as? [[String: Any]],
                  let json = dataArray.first else { return }
            
            do {
                // Dictionary -> Data -> Message (Model) dönüşümü
                let jsonData = try JSONSerialization.data(withJSONObject: json)
                let message = try JSONDecoder().decode(Message.self, from: jsonData)
                
                // Callback'i tetikle
                self?.onMessageReceived?(message)
                
            } catch {
                print("Mesaj parse hatası: \(error)")
            }
        }
    }
    
    // ViewModel'in socket'e erişmesi için gerekli
    func getSocket() -> SocketIOClient {
        return socket
    }
}
