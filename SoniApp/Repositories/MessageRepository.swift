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
    
    // MARK: - Private: DTO → Entity Mapping
    
    /// `Message` (DTO) → `MessageItem` (SwiftData Entity) dönüşümü.
    ///
    /// **Eskiden bu kod ChatViewModel.saveMessageToDB() içindeydi.**
    /// Şimdi tek bir yerde, gizli (encapsulated).
    /// Yeni bir alan eklersen (ör. `isRead`, `mediaURL`)
    /// sadece burayı değiştirirsin — ViewModel'e dokunmazsın.
    private func insertMessageItem(from message: Message) {
        // Statik formatter kullan (Date+ISO8601.swift'ten)
        let date = Date.fromISO8601(message.date ?? "") ?? Date()
        
        let newItem = MessageItem(
            id: message.id,
            text: message.text,
            senderId: message.senderId,
            receiverId: message.receiverId,
            date: date
        )
        
        // SwiftData @Attribute(.unique) sayesinde aynı ID'li mesaj
        // varsa üzerine yazar (upsert). Duplicate oluşmaz.
        modelContext.insert(newItem)
    }
}
