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
    
    /// **Yeni akış (local-first):**
    /// 1. Mesajı önce lokal SwiftData'ya `pending` olarak kaydet → UI'da hemen görünsün
    /// 2. Socket ile göndermeyi dene
    /// 3. Bağlantı varsa → `sent` (server tarafında da kaydedilir)
    /// 4. Bağlantı yoksa → `failed` olarak kalır, bağlantı gelince retry
    func sendMessage() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty,
              let myId = sessionStore?.currentUserId,
              let otherId = currentUser?.id else { return }
        
        let messageText = text
        text = ""
        
        // 1. Lokal ID oluştur — server'a da gönderilecek (echo'da eşleştirme için)
        let clientId = UUID().uuidString
        
        // 2. Lokal kaydet — pending durumda
        let pendingItem = MessageItem(
            id: clientId,
            text: messageText,
            senderId: myId,
            receiverId: otherId,
            date: Date(),
            senderName: sessionStore?.currentUsername ?? "",
            status: .pending
        )
        
        do {
            try messageRepository?.saveItem(pendingItem)
        } catch {
            print("❌ Save pending message error: \(error.localizedDescription)")
        }
        
        // 3. Socket ile gönder — clientId dahil
        // ÖNEMLİ: .pending olarak kalır! Echo geldiğinde subscribeToMessages
        // pending'i silip server versiyonunu kaydedecek.
        // Bu sayede WiFi kapalıyken emit sessizce başarısız olursa,
        // mesaj .pending kalır ve reconnect'te retry edilir.
        if chatService?.isConnected == true {
            chatService?.sendMessage(text: messageText, senderId: myId, receiverId: otherId, clientId: clientId)
            // Status .pending olarak kalıyor — echo gelince düzelecek
        } else {
            pendingItem.status = .failed
            try? messageRepository?.save()
        }
    }
    
    /// Bağlantı geldiğinde pending/failed mesajları tekrar gönder
    func retryPendingMessages() {
        guard let myId = sessionStore?.currentUserId,
              chatService?.isConnected == true else { return }
        
        let pendingMessages = messageRepository?.getPendingMessages(senderId: myId) ?? []
        
        for item in pendingMessages {
            // Retry — item.id clientId olarak gönderilir
            chatService?.sendMessage(text: item.text, senderId: item.senderId, receiverId: item.receiverId, clientId: item.id)
            // .pending olarak kalır — echo gelince subscribeToMessages düzeltecek
            // Failed olanları tekrar pending'e çevir (UI'da "not sent" yerine clock göster)
            if item.status == .failed {
                item.status = .pending
            }
        }
        
        try? messageRepository?.save()
    }
    
    // MARK: - Private Helpers
    
    private func isMessageRelevant(_ message: Message) -> Bool {
        guard let myId = sessionStore?.currentUserId,
              let otherId = currentUser?.id else { return false }
        
        return (message.senderId == otherId && message.receiverId == myId) ||
               (message.senderId == myId && message.receiverId == otherId)
    }
}
