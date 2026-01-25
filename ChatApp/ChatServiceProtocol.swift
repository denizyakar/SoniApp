//
//  ChatService.swift
//  ChatApp
//
//  Created by Ali Deniz Yakar on 24.01.2026.
//

import Foundation


// This is our "Contract". Any chat service MUST behave like this.
protocol ChatServiceProtocol {
    // A closure (callback) that triggers when a new message arrives.
    // Syntax explanation: It's a variable that holds a function.
    // { get set } means the conforming class must allow reading and writing to this variable.
    var onMessageReceived: ((Message) -> Void)? { get set }
    
    func connect()
    func sendMessage(text: String)
}

// A fake service for development and UI testing.
class MockChatService: ChatServiceProtocol {
    
    // We implement the variable required by the protocol.
    var onMessageReceived: ((Message) -> Void)?
    
    func connect() {
        print("[MockService] Connecting to fake server...")
        
        // Simulate receiving a welcome message after 1 second
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let welcomeMsg = Message(
                id: UUID(),
                text: "Welcome! This is the mock server.",
                isFromCurrentUser: false,
                date: Date()
            )
            // Trigger the closure if it exists (is not nil)
            self.onMessageReceived?(welcomeMsg)
        }
    }
    
    func sendMessage(text: String) {
        print("[MockService] Sending message: \(text)")
        
        // Simulate a reply from a friend after 1.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let replyMsg = Message(
                id: UUID(),
                text: "I received: '\(text)'. Nice to meet you!",
                isFromCurrentUser: false,
                date: Date()
            )
            // Notify the listener (ViewModel)
            self.onMessageReceived?(replyMsg)
        }
    }
}

