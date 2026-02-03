//
//  ChatViewModel.swift
//  SoniApp
//
//  Created by Ali Deniz Yakar on 25.01.2026.
//

import Foundation
import SocketIO
import Combine
import SwiftData

class ChatViewModel: ObservableObject {
    @Published var text = ""
    
    private var socketManager = SocketChatService.shared
    private var currentUser: ChatUser?
    
    // Access to SwiftData Context (to save data)
    private var modelContext: ModelContext?
    
    private let baseURL = "https://soni-app.xyz"
    
    // Setup now accepts ModelContext
    func setup(user: ChatUser, context: ModelContext) {
        self.currentUser = user
        self.modelContext = context
        
        fetchHistory()
        setupSocketListeners()
    }
    
    private func setupSocketListeners() {
        socketManager.getSocket().on("receive_message") { [weak self] data, ack in
            guard let self = self else { return }
            
            // Parse incoming JSON data
            if let dataArray = data as? [[String: Any]],
               let json = dataArray.first,
               let jsonData = try? JSONSerialization.data(withJSONObject: json),
               let message = try? JSONDecoder().decode(Message.self, from: jsonData) {
                
                // Save to DB if it belongs to this chat
                if self.isMessageRelevant(message) {
                    self.saveMessageToDB(message: message)
                }
            }
        }
    }
    
    // --- FETCH HISTORY FROM SERVER ---
    func fetchHistory() {
        guard let myId = AuthManager.shared.currentUserId,
              let otherId = currentUser?.id else { return }
        
        let urlString = "\(baseURL)/messages?from=\(myId)&to=\(otherId)"
        guard let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data = data, error == nil else { return }
            
            if let history = try? JSONDecoder().decode([Message].self, from: data) {
                DispatchQueue.main.async {
                    // Save every fetched message to local DB
                    // The UI will update automatically via @Query
                    for msg in history {
                        self?.saveMessageToDB(message: msg)
                    }
                }
            }
        }.resume()
    }
    
    // --- SEND MESSAGE ---
    func sendMessage() {
        print("sendmessage fonksiyonu çalıştı! bu 1 mi 2 mi?")
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty,
              let myId = AuthManager.shared.currentUserId,
              let otherId = currentUser?.id else { return }
        
        // 1. Send via Socket
        socketManager.sendMessage(text: text, receiverId: otherId)
        
        // Note: We don't save to DB here immediately.
        // We wait for the server/socket to echo it back to ensure consistency.
        
        text = ""
    }
    
    // --- HELPERS ---
    
    // Save Message struct to SwiftData MessageItem class
    private func saveMessageToDB(message: Message) {
        guard let context = modelContext else { return }
        
        // MongoDB dates are ISO8601 strings, convert to Date object
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: message.date ?? "") ?? Date()
        
        // Create new SwiftData item
        let newItem = MessageItem(
            id: message.id,
            text: message.text,
            senderId: message.senderId,
            receiverId: message.receiverId,
            date: date
        )
        
        // Insert into database
        context.insert(newItem)
        
        // Save context (ignoring errors for simplicity)
        try? context.save()
    }
    
    private func isMessageRelevant(_ message: Message) -> Bool {
        guard let myId = AuthManager.shared.currentUserId,
              let otherId = currentUser?.id else { return false }
        
        // Check if message is between ME and OTHER user
        return (message.senderId == otherId && message.receiverId == myId) ||
               (message.senderId == myId && message.receiverId == otherId)
    }
}
