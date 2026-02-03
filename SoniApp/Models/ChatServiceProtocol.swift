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
    func sendMessage(text: String, receiverId: String)
}

// A fake service for development and UI testing.
class SocketChatService: ChatServiceProtocol {
    // SINGLETON
    static let shared = SocketChatService()
    
    var onMessageReceived: ((Message) -> Void)?
    var onNewUserRegistered: (() -> Void)?
    
    private var manager: SocketManager
    private var socket: SocketIOClient
    
    private init() {
        // IP adress
        let url = URL(string: "https://soni-app.xyz")!
        
        manager = SocketManager(socketURL: url, config: [
            .log(true),
            .compress
        ])
        socket = manager.defaultSocket
        
        setupListeners()
    }
    
    func connect() {
        print("[SocketService] is connecting...")
        socket.connect()
    }
    
    // Note: The one who sends the messages is ChatViewModel but we still hold it here
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
        // When the connection is succesful
        socket.off(clientEvent: .connect)
        socket.on(clientEvent: .connect) { data, ack in
            print("[SocketService] is Connected! ✅")
        }
        
        // When a new user registers:
        socket.off("user_registered")
        
        socket.on("user_registered") { [weak self] data, ack in
            print("SOCKET: A new user just registered!")
            
            self?.onNewUserRegistered?()
                
        }
        
        
        socket.off("receive_message")
        // When a new message is received:
        socket.on("receive_message") { [weak self] data, ack in
            // Using Codable instead of parsing manually
            guard let dataArray = data as? [[String: Any]],
                  let json = dataArray.first else { return }
            
            do {
                // Dictionary -> Data -> Message (Model) conversion
                let jsonData = try JSONSerialization.data(withJSONObject: json)
                let message = try JSONDecoder().decode(Message.self, from: jsonData)
                
                print("Message from Socket: - id:\(message.id) - Text: \(message.text)")
                
                // Trigger Callback
                self?.onMessageReceived?(message)
                
            } catch {
                print("Message parse error: \(error)")
            }
        }
    }
    
    // Necessary for ViewModel to access Socket
    func getSocket() -> SocketIOClient {
        return socket
    }
}
