//
//  ChatViewModel.swift
//  ChatApp
//
//  Created by Ali Deniz Yakar on 25.01.2026.
//

import Foundation
import Combine

// ObservableObject: Allows the UI to listen for changes in this class.
class ChatViewModel: ObservableObject {
    
    // @Published: When these variables change, the UI automatically redraws.
    @Published var messages: [Message] = []
    @Published var currentInputText: String = ""
    
    // We use the Protocol type here, not the specific class (MockChatService).
    // This is "Polymorphism". The ViewModel doesn't know it's using a fake service.
    
    let user: ChatUser
    private var chatService: ChatServiceProtocol
    
    // Dependency Injection: We ask for the service in the initializer.
    // Default value is MockChatService, but we can swap it later.
    init(user: ChatUser, service: ChatServiceProtocol = MockChatService()) {
        self.user = user
        self.chatService = service
        setupBindings()
        self.chatService.connect()
    }
    
    // Private function to keep the init clean
    private func setupBindings() {
        // Here we assign OUR function to the Service's "empty seat" (closure).
        // [weak self] prevents memory leaks (retain cycles).
        self.chatService.onMessageReceived = { [weak self] incomingMessage in
            // UI updates must happen on the Main Thread
            DispatchQueue.main.async {
                self?.messages.append(incomingMessage)
            }
        }
    }
    
    func sendMessage() {
        let trimmedText = currentInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        // 1. Optimistic UI Update: Show the message immediately on screen
        let newMessage = Message(
            id: UUID(),
            text: trimmedText,
            isFromCurrentUser: true,
            date: Date()
        )
        messages.append(newMessage)
        
        // 2. Send to backend
        chatService.sendMessage(text: trimmedText)
        
        // 3. Clear input
        currentInputText = ""
    }
}
