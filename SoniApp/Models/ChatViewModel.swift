//
//  ChatViewModel.swift
//  SoniApp
//

import Foundation
import Combine
import SwiftData
import UIKit

@MainActor
class ChatViewModel: ObservableObject {
    
    // MARK: - UI State
    @Published var text = ""
    
    private var chatService: SocketChatService?
    private var sessionStore: SessionStoreProtocol?
    private var messageRepository: MessageRepository?
    
    private var currentUser: ChatUser?
    private var cancellables = Set<AnyCancellable>()
    private var isSetUp = false
    
    // MARK: - Setup
    
    func setup(user: ChatUser, context: ModelContext, chatService: SocketChatService, sessionStore: SessionStoreProtocol) {
        guard !isSetUp else { return }
        isSetUp = true
        
        self.currentUser = user
        self.chatService = chatService
        self.sessionStore = sessionStore
        self.messageRepository = MessageRepository(modelContext: context)
        
        fetchHistory()
        subscribeToMessages()
        subscribeToReadReceipts()
        subscribeToConnectionState()
        
        markUnreadMessagesAsRead()
        
        // Re-mark when app returns from background
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.markUnreadMessagesAsRead()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Fetch History
    
    private func fetchHistory() {
        guard let myId = sessionStore?.currentUserId,
              let otherId = currentUser?.id else { return }
        
        Task {
            do {
                try await messageRepository?.fetchHistory(myId: myId, otherId: otherId)
                // Re-mark as read after history loads
                markUnreadMessagesAsRead()
            } catch {
                print("❌ Fetch history error: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Socket Subscription
    
    private func subscribeToMessages() {
        chatService?.messagePublisher
            .receive(on: DispatchQueue.main)
            .filter { [weak self] message in
                self?.isMessageRelevant(message) ?? false
            }
            .sink { [weak self] message in
                guard let self = self else { return }
                do {
                    // Server echo — replace local pending message with server version
                    if message.senderId == self.sessionStore?.currentUserId {
                        if let clientId = message.clientId {
                            try? self.messageRepository?.deleteMessage(id: clientId)
                        }
                        try self.messageRepository?.saveMessage(message)
                    } else {
                        // Incoming message
                        try self.messageRepository?.saveMessage(message)
                        if UIApplication.shared.applicationState == .active {
                            self.sendReadReceipt(for: [message.id])
                        }
                    }
                } catch {
                    print("❌ Save message error: \(error.localizedDescription)")
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Read Receipts
    
    /// Subscribe to read receipts to update message status
    private func subscribeToReadReceipts() {
        chatService?.messageReadPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messageIds in
                self?.messageRepository?.markAsRead(messageIds: messageIds)
            }
            .store(in: &cancellables)
    }
    
    /// Retry pending messages on reconnect
    private func subscribeToConnectionState() {
        chatService?.connectionStatePublisher
            .receive(on: DispatchQueue.main)
            .filter { $0 == true }
            .sink { [weak self] _ in
                self?.retryPendingMessages()
            }
            .store(in: &cancellables)
    }
    
    private func markUnreadMessagesAsRead() {
        guard let myId = sessionStore?.currentUserId,
              let otherId = currentUser?.id else { return }
        
        let unreadIds = messageRepository?.getUnreadMessageIds(from: otherId, to: myId) ?? []
        if !unreadIds.isEmpty {
            sendReadReceipt(for: unreadIds)
            messageRepository?.markAsRead(messageIds: unreadIds)
        }
    }
    
    private func sendReadReceipt(for messageIds: [String]) {
        guard let myId = sessionStore?.currentUserId else { return }
        chatService?.sendReadReceipt(messageIds: messageIds, readerId: myId)
    }
    
    // MARK: - Delete Message
    
    func deleteMessage(id: String) {
        do {
            try messageRepository?.deleteMessage(id: id)
        } catch {
            print("❌ Delete message error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Send Message (Offline Queue)
    
    // MARK: - Retry Logic
    
    /// Retry pending/failed messages on reconnect
    func retryPendingMessages() {
        guard let myId = sessionStore?.currentUserId,
              chatService?.isConnected == true else { return }
        
        // Get pending messages on MainActor
        let pendingMessages = messageRepository?.getPendingMessages(senderId: myId) ?? []
        
        // Start retry (async)
        Task {
            for item in pendingMessages {
                // Skip if already being processed
                // Keeping it simple for now.
                
                var finalImageUrl = item.imageUrl
                
                // If image URL is local (file://), upload first
                if let urlString = item.imageUrl, urlString.hasPrefix("file://"),
                   let localUrl = URL(string: urlString) {
                    
                    do {
                        if FileManager.default.fileExists(atPath: localUrl.path) {
                            let data = try Data(contentsOf: localUrl)
                            let serverUrl = try await chatService?.uploadMessageImage(data)
                            await MainActor.run {
                                item.imageUrl = serverUrl
                                try? messageRepository?.save()
                            }
                            finalImageUrl = serverUrl
                        } else {
                            print("❌ Retry: Local file missing")
                        }
                    } catch {
                        print("❌ Retry upload failed: \(error)")
                        // Upload failed, skip this message
                        continue
                    }
                }
                
                // Socket emit (text + optional server image URL)
                sendSocketMessage(
                    text: item.text,
                    clientId: item.id,
                    imageUrl: finalImageUrl
                )
                
                // Update status
                await MainActor.run {
                    if item.status == .failed {
                        item.status = .pending
                        try? messageRepository?.save()
                    }
                }
            }
        }
    }

    // MARK: - Send Message (Unified Text + Image)
    
    /// Sends a message with optional image.
    func sendMessage(image: UIImage? = nil) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedText.isEmpty || image != nil,
              let myId = sessionStore?.currentUserId,
              let otherId = currentUser?.id else { return }
        
        let messageText = text
        text = ""
        
        let clientId = UUID().uuidString
        let date = Date()
        
        // Save image to local persistent storage first
        var localImageUrl: String? = nil
        if let image = image {
            localImageUrl = saveImageToLocalCache(image: image)
        }
        
        // Create pending message item
        let pendingItem = MessageItem(
            id: clientId,
            text: messageText,
            senderId: myId,
            receiverId: otherId,
            date: date,
            senderName: sessionStore?.currentUsername ?? "",
            status: .pending,
            imageUrl: localImageUrl
        )
        
        do {
            try messageRepository?.saveItem(pendingItem)
        } catch {
            print("❌ Save pending message error: \(error.localizedDescription)")
        }
        
        // Async: upload + socket emit
        Task {
            // Text only
            if image == nil {
                sendSocketMessage(text: messageText, clientId: clientId, imageUrl: nil)
                return
            }
            
            // Image: upload then send
            do {
                guard let image = image,
                      let data = image.jpegData(compressionQuality: 0.7) else { return }
                
                let serverImageUrl = try await chatService?.uploadMessageImage(data)
                sendSocketMessage(text: messageText, clientId: clientId, imageUrl: serverImageUrl)
                
            } catch {
                print("❌ Image upload failed: \(error)")
                await MainActor.run {
                    pendingItem.status = .failed
                    try? messageRepository?.save()
                }
            }
        }
    }
    
    /// Emit message via socket
    @MainActor
    private func sendSocketMessage(text: String, clientId: String, imageUrl: String?) {
        guard let myId = sessionStore?.currentUserId,
              let otherId = currentUser?.id,
              chatService?.isConnected == true else {
            // No connection — mark as failed
            if let item = try? messageRepository?.getMessage(byId: clientId) {
                item.status = .failed
                try? messageRepository?.save()
            }
            return
        }
        
        chatService?.sendMessage(
            text: text,
            senderId: myId,
            receiverId: otherId,
            clientId: clientId,
            imageUrl: imageUrl
        )
        // Stays pending until server echo arrives
    }
    
    /// Save image to Documents/PendingImages (persistent across app restarts)
    private func saveImageToLocalCache(image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        
        let folderURL = documentsURL.appendingPathComponent("PendingImages")
        if !fileManager.fileExists(atPath: folderURL.path) {
            try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        
        let fileName = "pending_\(UUID().uuidString).jpg"
        let fileUrl = folderURL.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileUrl)
            return fileUrl.absoluteString
        } catch {
            print("❌ Local image save error: \(error)")
            return nil
        }
    }
    
    // MARK: - Private Helpers
    
    private func isMessageRelevant(_ message: Message) -> Bool {
        guard let myId = sessionStore?.currentUserId,
              let otherId = currentUser?.id else { return false }
        
        return (message.senderId == otherId && message.receiverId == myId) ||
               (message.senderId == myId && message.receiverId == otherId)
    }
}

