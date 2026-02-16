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
//

import Foundation
import Combine
import SwiftData

/// Chat ekranını yöneten ViewModel.
///
/// **MVVM'de ViewModel'in görevi:**
/// - View'dan gelen user action'ları almak (sendMessage, loadHistory)
/// - İş mantığını çalıştırmak (repository'ye delege ederek)
/// - UI state'ini güncellemek (@Published properties)
///
/// **ViewModel'in bilMEMESİ gerekenler:**
/// - Verinin nereden geldiği (Socket? REST? Cache?)
/// - Verinin nereye kaydedildiği (SwiftData? Core Data? Realm?)
/// - Network protokolü detayları (Socket.IO? WebSocket? gRPC?)
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
    
    // MARK: - Setup
    
    /// View'dan çağrılır. Tüm bağımlılıkları inject eder ve dinlemeye başlar.
    ///
    /// **Neden init'te değil de setup'ta?**
    /// SwiftUI'de @EnvironmentObject init'te mevcut değildir.
    /// Bu yüzden bağımlılıklar .onAppear'da inject ediliyor.
    func setup(user: ChatUser, context: ModelContext, chatService: SocketChatService, sessionStore: SessionStoreProtocol) {
        self.currentUser = user
        self.chatService = chatService
        self.sessionStore = sessionStore
        self.messageRepository = MessageRepository(modelContext: context)
        
        fetchHistory()
        subscribeToMessages()
    }
    
    // MARK: - Fetch History
    
    /// **Eskiden:** ViewModel içinde URLSession kodu, inline JSON decode
    /// **Şimdi:** Repository'ye tek satırlık çağrı
    private func fetchHistory() {
        guard let myId = sessionStore?.currentUserId,
              let otherId = currentUser?.id else { return }
        
        Task {
            do {
                try await messageRepository?.fetchHistory(myId: myId, otherId: otherId)
            } catch {
                print("❌ Fetch history error: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Subscribe to Socket Messages
    
    /// **Eskiden:**
    /// ```swift
    /// socketManager.getSocket().on("receive_message") { data, ack in
    ///     // Raw socket erişimi + JSON parse + DB kayıt hepsi burada
    /// }
    /// ```
    ///
    /// **Şimdi:**
    /// Combine publisher subscribe ediyoruz. Socket.IO detaylarını bilmiyoruz.
    /// Sadece `Message` objesi geliyor.
    private func subscribeToMessages() {
        chatService?.messagePublisher
            .receive(on: DispatchQueue.main)
            .filter { [weak self] message in
                self?.isMessageRelevant(message) ?? false
            }
            .sink { [weak self] message in
                guard let self = self else { return }
                do {
                    try self.messageRepository?.saveMessage(message)
                } catch {
                    print("❌ Save message error: \(error.localizedDescription)")
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Send Message
    
    func sendMessage() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty,
              let myId = sessionStore?.currentUserId,
              let otherId = currentUser?.id else { return }
        
        chatService?.sendMessage(text: text, senderId: myId, receiverId: otherId)
        text = ""
    }
    
    // MARK: - Private Helpers
    
    private func isMessageRelevant(_ message: Message) -> Bool {
        guard let myId = sessionStore?.currentUserId,
              let otherId = currentUser?.id else { return false }
        
        return (message.senderId == otherId && message.receiverId == myId) ||
               (message.senderId == myId && message.receiverId == otherId)
    }
}
