//
//  MessageRepository.swift
//  SoniApp
//
//  Mesaj verisi koordinasyonu: Network ↔ SwiftData arasındaki köprü.
//  Eskiden bu mantık ChatViewModel'in içinde dağınıktı.
//

import Foundation
import SwiftData
import Combine

// MARK: - Protocol

/// Mesaj veri operasyonlarının sözleşmesi.
///
/// **Neden Repository Pattern?**
/// ChatViewModel eskiden şunları yapıyordu:
/// 1. REST API'den mesaj geçmişi çek (URLSession inline kod)
/// 2. Socket'ten gelen mesajı parse et
/// 3. Message → MessageItem mapping yap
/// 4. ISO8601 tarih parse et
/// 5. SwiftData context.insert() + save()
///
/// ViewModel'in görevi SADECE UI state yönetmek olmalı. Veri nereden gelir,
/// nereye kaydedilir — bunlar ViewModel'in bilmesi gereken şeyler değil.
/// Repository Pattern bu mantığı tek bir yerde toplar.
///
/// **Martin Fowler:** "A Repository mediates between the domain and data mapping
/// layers, acting like an in-memory domain object collection."
protocol MessageRepositoryProtocol {
    /// Sunucudan mesaj geçmişini çeker ve lokal DB'ye kaydeder.
    func fetchHistory(myId: String, otherId: String) async throws
    
    /// Tek bir mesajı lokal DB'ye kaydeder (socket'ten gelen).
    func saveMessage(_ message: Message) throws
}

// MARK: - Implementation

/// SwiftData tabanlı mesaj repository'si.
///
/// **Mapping mantığı burada:**
/// `Message` (network DTO, struct) → `MessageItem` (SwiftData @Model, class)
/// dönüşümü artık ViewModel'de değil, burada yapılıyor.
///
/// **Neden `@ModelActor`?**
/// SwiftData context'i thread-safe değildir. `@ModelActor` ile
/// repository kendi actor'ünde çalışır — main thread'i bloklamaz.
/// Ancak bu ilk versiyon basitlik için MainActor kullanıyor.
/// İleride `@ModelActor` geçişi yapılabilir.
@MainActor
final class MessageRepository: MessageRepositoryProtocol {
    
    private let modelContext: ModelContext
    
    // Network config (AuthService'le aynı proxy-free config)
    private var session: URLSession {
        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 30.0
        return URLSession(configuration: config)
    }
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Fetch History from Server
    
    func fetchHistory(myId: String, otherId: String) async throws {
        let url = APIEndpoints.messages(from: myId, to: otherId)
        
        let (data, _) = try await session.data(from: url)
        
        let messages = try JSONDecoder().decode([Message].self, from: data)
        
        // Batch insert — her mesaj için ayrı save() çağırmak yerine
        // hepsini ekleyip tek seferde save() çağırıyoruz.
        // Bu, disk I/O'yu azaltır.
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
    
    // MARK: - Save MessageItem (for offline queue)
    
    /// Doğrudan MessageItem kaydet (pending mesajlar için)
    func saveItem(_ item: MessageItem) throws {
        modelContext.insert(item)
        try modelContext.save()
    }
    
    /// Context'i kaydet (status güncellemeleri için)
    func save() throws {
        try modelContext.save()
    }
    
    // MARK: - Pending Messages (offline queue)
    
    /// Gönderilmeyi bekleyen (pending/failed) mesajları getir
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
    
    /// Belirtilen mesajları "okundu" olarak işaretle
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
    
    /// Belirli bir göndericiden bana gelen okunmamış mesaj ID'lerini getir
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
    
    // MARK: - Delete Message (lokal)
    
    /// Mesajı lokal SwiftData'dan sil (Delete from me)
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
    
    // MARK: - Get Single Message
    
    /// Tek bir mesajı ID ile getir
    func getMessage(byId id: String) throws -> MessageItem? {
        let predicate = #Predicate<MessageItem> { item in
            item.id == id
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        let results = try modelContext.fetch(descriptor)
        return results.first
    }
    
    // MARK: - Private: DTO → Entity Mapping
    
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
            imageUrl: message.imageUrl // YENİ: Görsel URL'i kaydet
        )
        
        modelContext.insert(newItem)
    }
}
