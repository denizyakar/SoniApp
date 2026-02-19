//
//  ChatViewModel.swift
//  SoniApp
//
//  TAMAMEN YENİDEN YAZILDI.
//
//  Önceki sorunlar:
//  1. SocketChatService.shared — singleton doğrudan erişim
//  2. getSocket().on() — raw socket erişimi (leaky abstraction)
//  3. AuthManager.shared.currentUserId — model seviyesinde singleton
//  4. URLSession inline — ViewModel'de network kodu
//  5. ISO8601DateFormatter her seferinde yeniden yaratılıyor
//  6. try? context.save() — sessiz hata yutma
//  7. saveMessageToDB() — DTO→Entity mapping ViewModel'de
//
//  Şimdi:
//  - Dependencies setup()'ta inject ediliyor
//  - Socket mesajları Combine publisher ile geliyor
//  - Tüm veri operasyonları Repository'de
//  - ViewModel sadece UI state yönetiyor
//  - Read receipt desteği eklendi
//

import Foundation
import Combine
import SwiftData
import UIKit

@MainActor
class ChatViewModel: ObservableObject {
    
    // MARK: - UI State
    @Published var text = ""
    
    // MARK: - Dependencies (setup'ta inject edilen)
    
    private var chatService: SocketChatService?
    private var sessionStore: SessionStoreProtocol?
    private var messageRepository: MessageRepository?
    
    // MARK: - Private
    
    private var currentUser: ChatUser?
    private var cancellables = Set<AnyCancellable>()
    private var isSetUp = false  // ← Duplicate setup önleme
    
    // MARK: - Setup
    
    func setup(user: ChatUser, context: ModelContext, chatService: SocketChatService, sessionStore: SessionStoreProtocol) {
        // onAppear her çağrıldığında tekrar subscribe olmayı önle
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
        
        // Chat açıldığında karşıdan gelen okunmamış mesajları okundu işaretle
        markUnreadMessagesAsRead()
    }
    
    // MARK: - Fetch History
    
    private func fetchHistory() {
        guard let myId = sessionStore?.currentUserId,
              let otherId = currentUser?.id else { return }
        
        Task {
            do {
                try await messageRepository?.fetchHistory(myId: myId, otherId: otherId)
                // History yüklendikten sonra tekrar okundu işaretle
                markUnreadMessagesAsRead()
            } catch {
                print("❌ Fetch history error: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Subscribe to Socket Messages
    
    private func subscribeToMessages() {
        chatService?.messagePublisher
            .receive(on: DispatchQueue.main)
            .filter { [weak self] message in
                self?.isMessageRelevant(message) ?? false
            }
            .sink { [weak self] message in
                guard let self = self else { return }
                do {
                    // Eğer bu mesaj benim gönderdiğim bir mesajın server echo'suysa
                    // lokal pending kaydı sil, server versiyonunu kaydet
                    if message.senderId == self.sessionStore?.currentUserId {
                        // Server echo — pending/lokal mesajı server'dan gelen gerçek ID ile değiştir
                        if let clientId = message.clientId {
                            try? self.messageRepository?.deleteMessage(id: clientId)
                        }
                        try self.messageRepository?.saveMessage(message)
                    } else {
                        // Karşıdan gelen mesaj
                        try self.messageRepository?.saveMessage(message)
                        // Chat açıksa hemen okundu işaretle
                        self.sendReadReceipt(for: [message.id])
                    }
                } catch {
                    print("❌ Save message error: \(error.localizedDescription)")
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Read Receipts
    
    /// Read receipt'leri dinle — kendi mesajlarımızın okundu durumunu güncelle
    private func subscribeToReadReceipts() {
        chatService?.messageReadPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messageIds in
                self?.messageRepository?.markAsRead(messageIds: messageIds)
            }
            .store(in: &cancellables)
    }
    
    /// Bağlantı durumunu dinle — reconnect olunca pending mesajları retry et
    private func subscribeToConnectionState() {
        chatService?.connectionStatePublisher
            .receive(on: DispatchQueue.main)
            .filter { $0 == true }  // Sadece bağlandığında
            .sink { [weak self] _ in
                self?.retryPendingMessages()
            }
            .store(in: &cancellables)
    }
    
    /// Chat açıldığında karşıdan gelen okunmamış mesajları "read" işaretle
    private func markUnreadMessagesAsRead() {
        guard let myId = sessionStore?.currentUserId,
              let otherId = currentUser?.id else { return }
        
        let unreadIds = messageRepository?.getUnreadMessageIds(from: otherId, to: myId) ?? []
        if !unreadIds.isEmpty {
            sendReadReceipt(for: unreadIds)
            messageRepository?.markAsRead(messageIds: unreadIds)
        }
    }
    
    /// Server'a "bu mesajları okudum" bilgisi gönder
    private func sendReadReceipt(for messageIds: [String]) {
        guard let myId = sessionStore?.currentUserId else { return }
        chatService?.sendReadReceipt(messageIds: messageIds, readerId: myId)
    }
    
    // MARK: - Delete Message (lokal)
    
    /// Mesajı sadece lokal SwiftData'dan sil (Delete from me)
    func deleteMessage(id: String) {
        do {
            try messageRepository?.deleteMessage(id: id)
        } catch {
            print("❌ Delete message error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Send Message (Offline Queue)
    
    // MARK: - Retry Logic
    
    /// Bağlantı geldiğinde pending/failed mesajları tekrar gönder
    func retryPendingMessages() {
        guard let myId = sessionStore?.currentUserId,
              chatService?.isConnected == true else { return }
        
        // MainActor'de pending mesajları al
        let pendingMessages = messageRepository?.getPendingMessages(senderId: myId) ?? []
        
        // Retry işlemini başlat (Asenkron)
        Task {
            for item in pendingMessages {
                // Zaten işlem yapılıyorsa atla (örneğin pending status'unda upload'da)
                // Ama şimdilik basit tutalım.
                
                var finalImageUrl = item.imageUrl
                
                // 1. Resim varsa ve LOCAL URL ise (file://) → Önce Upload Et
                if let urlString = item.imageUrl, urlString.hasPrefix("file://"),
                   let localUrl = URL(string: urlString) {
                    
                    do {
                        // Dosya var mı kontrol et
                        if FileManager.default.fileExists(atPath: localUrl.path) {
                            let data = try Data(contentsOf: localUrl)
                            // Upload
                            let serverUrl = try await chatService?.uploadMessageImage(data)
                            // Başarılı! DB'yi güncelle
                            await MainActor.run {
                                item.imageUrl = serverUrl
                                try? messageRepository?.save()
                            }
                            finalImageUrl = serverUrl
                        } else {
                            // Dosya yoksa yapacak bir şey yok, hatayı logla
                            print("❌ Retry: Local file missing for pending message")
                        }
                    } catch {
                        print("❌ Retry upload failed: \(error)")
                        // Upload başarısızsa bu turu pas geç (sonra tekrar dener)
                        continue
                    }
                }
                
                // 2. Socket ile gönder (Text + (Varsa) Server Image URL)
                sendSocketMessage(
                    text: item.text,
                    clientId: item.id,
                    imageUrl: finalImageUrl
                )
                
                // Status güncellemesi (failed -> pending)
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
    
    /// Hem yazıyı hem de (varsa) resmi gönderir.
    /// Resim varsa:
    /// 1. Önce lokal diske kaydet (Pending modda hemen ekranda görünsün)
    /// 2. Upload et
    /// 3. Socket'ten URL ile gönder
    func sendMessage(image: UIImage? = nil) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Boş mesaj gönderme (hem yazı yok hem resim yoksa)
        guard !trimmedText.isEmpty || image != nil,
              let myId = sessionStore?.currentUserId,
              let otherId = currentUser?.id else { return }
        
        let messageText = text
        text = "" // UI'ı temizle
        
        let clientId = UUID().uuidString
        let date = Date()
        
        // 1. Resim varsa önce LOKAL (Persistent) URL oluştur
        // Böylece upload bitmeden ekranda resmi görebiliriz ve uygulama kapansa bile silinmez.
        var localImageUrl: String? = nil
        if let image = image {
            localImageUrl = saveImageToLocalCache(image: image)
        }
        
        // 2. Pending Item oluştur (Lokal URL ile)
        let pendingItem = MessageItem(
            id: clientId,
            text: messageText,
            senderId: myId,
            receiverId: otherId,
            date: date,
            senderName: sessionStore?.currentUsername ?? "",
            status: .pending,
            imageUrl: localImageUrl // Lokal dosya yolu
        )
        
        do {
            try messageRepository?.saveItem(pendingItem)
        } catch {
            print("❌ Save pending message error: \(error.localizedDescription)")
        }
        
        // 3. Asenkron işlem başlat (Upload + Socket)
        Task {
            // A) Sadece yazı varsa
            if image == nil {
                sendSocketMessage(text: messageText, clientId: clientId, imageUrl: nil)
                return
            }
            
            // B) Resim varsa → önce Upload
            do {
                guard let image = image,
                      let data = image.jpegData(compressionQuality: 0.7) else { return }
                
                // Upload'a başla...
                // (İstersek pendingItem.text'i "Uploading..." yapabiliriz ama gerek yok, kullanıcı kendi yazdığını görsün)
                
                let serverImageUrl = try await chatService?.uploadMessageImage(data)
                
                // Upload bitti, şimdi sunucudan gelen URL ile socket mesajı at
                sendSocketMessage(text: messageText, clientId: clientId, imageUrl: serverImageUrl)
                
            } catch {
                print("❌ Image upload failed: \(error)")
                await MainActor.run {
                    pendingItem.status = .failed
                    // pendingItem.text = "❌ Upload Failed" // YAPMA: Orijinal içeriği koru!
                    try? messageRepository?.save()
                }
            }
        }
    }
    
    /// Socket üzerinden mesajı gönderir (MainActor üzerinde çalışır)
    @MainActor
    private func sendSocketMessage(text: String, clientId: String, imageUrl: String?) {
        guard let myId = sessionStore?.currentUserId,
              let otherId = currentUser?.id,
              chatService?.isConnected == true else {
            // Bağlantı yoksa failed işaretle
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
        // Başarılı emit sonrası pending olarak kalır, echo gelince düzelir.
    }
    
    /// Resmi Documents/PendingImages klasörüne kaydeder ve file URL döndürür
    /// (Persistent Storage: Uygulama yeniden başlasa bile silinmez)
    private func saveImageToLocalCache(image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        
        // "PendingImages" alt klasörü
        let folderURL = documentsURL.appendingPathComponent("PendingImages")
        
        // Klasör yoksa yarat
        if !fileManager.fileExists(atPath: folderURL.path) {
            try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        
        let fileName = "pending_\(UUID().uuidString).jpg"
        let fileUrl = folderURL.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileUrl)
            return fileUrl.absoluteString // file:///...
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

