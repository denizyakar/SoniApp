//
//  PendingMessageRetryService.swift
//  SoniApp
//

import Foundation
import Combine
import SwiftData

/// App-wide pending mesaj retry servisi.
///
/// **Why was the timer removed?**
/// The timer sent messages every 5s, but without a server echo they
/// stayed .pending → infinite loop. Marking as .sent risked silent
/// message loss if socket emit failed.
/// Reliable triggers are used instead.
@MainActor
final class PendingMessageRetryService {
    
    private let chatService: SocketChatService
    private let sessionStore: SessionStoreProtocol
    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    private var isSetUp = false
    
    init(chatService: SocketChatService, sessionStore: SessionStoreProtocol) {
        self.chatService = chatService
        self.sessionStore = sessionStore
    }
    
    /// Called when ModelContext becomes available (first view load).
    func setup(modelContext: ModelContext) {
        guard !isSetUp else { return }
        isSetUp = true
        self.modelContext = modelContext
        
        // Debounce to handle connection flaps
        chatService.connectionStatePublisher
            .removeDuplicates()
            .filter { $0 == true }
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                print("🔄 Retry trigger: socket reconnected")
                self?.retryAllPendingMessages()
            }
            .store(in: &cancellables)
        
        // Run initial check on setup
        if chatService.isConnected {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.retryAllPendingMessages()
            }
        }
    }
    
    /// Retry all pending/failed messages.
    func retryAllPendingMessages() {
        guard let modelContext = modelContext,
              let myId = sessionStore.currentUserId,
              chatService.isConnected else { return }
        
        let pendingRaw = MessageStatus.pending.rawValue
        let failedRaw = MessageStatus.failed.rawValue
        
        let predicate = #Predicate<MessageItem> { item in
            item.senderId == myId &&
            (item.statusRaw == pendingRaw || item.statusRaw == failedRaw)
        }
        
        do {
            let pendingMessages = try modelContext.fetch(
                FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.date)])
            )
            
            guard !pendingMessages.isEmpty else { return }
            
            print("🔄 Retrying \(pendingMessages.count) pending messages (app-wide)")
            
            for item in pendingMessages {
                chatService.sendMessage(
                    text: item.text,
                    senderId: item.senderId,
                    receiverId: item.receiverId,
                    clientId: item.id,
                    imageUrl: item.imageUrl
                )
                
                item.status = .sent
            }
            
            try modelContext.save()
            print("✅ Retry complete: \(pendingMessages.count) messages marked as sent")
        } catch {
            print("❌ App-wide retry error: \(error.localizedDescription)")
        }
    }
}
