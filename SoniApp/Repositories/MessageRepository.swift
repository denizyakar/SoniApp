//
//  MessageRepository.swift
//  SoniApp
//

import Foundation
import SwiftData

// MARK: - Protocol

protocol MessageRepositoryProtocol {
    func fetchHistory(myId: String, otherId: String) async throws
    func saveMessage(_ message: Message) throws
}

// MARK: - Implementation

@MainActor
final class MessageRepository: MessageRepositoryProtocol {
    
    private let modelContext: ModelContext
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 30.0
        return URLSession(configuration: config)
    }()
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Fetch History from Server
    
    func fetchHistory(myId: String, otherId: String) async throws {
        let url = APIEndpoints.messages(from: myId, to: otherId)
        
        let (data, _) = try await session.data(from: url)
        
        let messages = try JSONDecoder().decode([Message].self, from: data)
        
        // Batch insert
        for msg in messages {
            insertMessageItem(from: msg)
        }
        
        try modelContext.save()
    }
    
    // MARK: - Save Single Message (from Socket)
    
    func saveMessage(_ message: Message) throws {
        insertMessageItem(from: message)
        try modelContext.save()
    }
    
    func saveItem(_ item: MessageItem) throws {
        modelContext.insert(item)
        try modelContext.save()
    }
    
    func save() throws {
        try modelContext.save()
    }
    
    // MARK: - Pending Messages (offline queue)
    
    /// Get pending/failed messages for retry
    func getPendingMessages(senderId: String) -> [MessageItem] {
        let pendingRaw = MessageStatus.pending.rawValue
        let failedRaw = MessageStatus.failed.rawValue
        
        let predicate = #Predicate<MessageItem> { item in
            item.senderId == senderId &&
            (item.statusRaw == pendingRaw || item.statusRaw == failedRaw)
        }
        
        do {
            return try modelContext.fetch(FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.date)]))
        } catch {
            print("❌ Get pending messages error: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - Read Receipts
    
    func markAsRead(messageIds: [String]) {
        let predicate = #Predicate<MessageItem> { item in
            item.isRead == false
        }
        
        do {
            let allUnread = try modelContext.fetch(FetchDescriptor(predicate: predicate))
            let now = Date()
            
            for item in allUnread where messageIds.contains(item.id) {
                item.isRead = true
                item.readAt = now
            }
            
            try modelContext.save()
        } catch {
            print("❌ Mark as read error: \(error.localizedDescription)")
        }
    }
    
    func getUnreadMessageIds(from senderId: String, to receiverId: String) -> [String] {
        let predicate = #Predicate<MessageItem> { item in
            item.senderId == senderId &&
            item.receiverId == receiverId &&
            item.isRead == false
        }
        
        do {
            let unread = try modelContext.fetch(FetchDescriptor(predicate: predicate))
            return unread.map { $0.id }
        } catch {
            print("❌ Get unread IDs error: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - Delete
    
    func deleteMessage(id: String) throws {
        let predicate = #Predicate<MessageItem> { item in
            item.id == id
        }
        
        let items = try modelContext.fetch(FetchDescriptor(predicate: predicate))
        for item in items {
            modelContext.delete(item)
        }
        try modelContext.save()
    }
    
    func getMessage(byId id: String) throws -> MessageItem? {
        let predicate = #Predicate<MessageItem> { item in
            item.id == id
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        let results = try modelContext.fetch(descriptor)
        return results.first
    }
    
    // MARK: - DTO → Entity Mapping
    
    private func insertMessageItem(from message: Message) {
        let date = Date.fromISO8601(message.date ?? "") ?? Date()
        let readAt = message.readAt.flatMap { Date.fromISO8601($0) }
        
        let newItem = MessageItem(
            id: message.id,
            text: message.text,
            senderId: message.senderId,
            receiverId: message.receiverId,
            date: date,
            senderName: message.senderName ?? "",
            isRead: message.isRead ?? false,
            readAt: readAt,
            imageUrl: message.imageUrl
        )
        
        modelContext.insert(newItem)
    }
}
