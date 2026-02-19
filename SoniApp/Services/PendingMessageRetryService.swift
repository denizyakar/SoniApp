//
//  PendingMessageRetryService.swift
//  SoniApp
//
//  App-wide bekleyen mesaj retry servisi.
//  ChatViewModel'den bağımsız çalışır — hangi View açık olursa olsun
//  socket reconnect olduğunda pending mesajları yeniden gönderir.
//
//  v3: Timer KALDIRILDI (sonsuz döngü + false-positive .sent sorunu).
//      Retry şimdi sadece güvenilir anlarda tetikleniyor:
//      1. Socket reconnect (connectionStatePublisher)
//      2. App foreground (scenePhase.active)
//      3. ChatView açılışı (onAppear)
//

import Foundation
import Combine
import SwiftData

/// App-wide pending mesaj retry servisi.
///
/// **Neden timer kaldırıldı?**
/// Timer her 5sn'de mesajları gönderiyordu ama server echo'su olmazsa
/// mesajlar .pending kalıyor → sonsuz döngü. .sent olarak işaretlersek
/// de socket emit sessizce başarısız olursa mesaj kayboluyordu.
/// Timer yerine güvenilir tetikleyiciler kullanılıyor.
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
    
    /// ModelContext geldiğinde çağrılır (ilk View yüklendiğinde).
    func setup(modelContext: ModelContext) {
        guard !isSetUp else { return }
        isSetUp = true
        self.modelContext = modelContext
        
        // Socket bağlantısı geldiğinde retry yap
        // debounce: bağlantı flap'lerini (connect/disconnect/connect) birleştirir
        chatService.connectionStatePublisher
            .removeDuplicates()
            .filter { $0 == true }
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                print("🔄 Retry trigger: socket reconnected")
                self?.retryAllPendingMessages()
            }
            .store(in: &cancellables)
        
        // İlk setup'ta da bir kontrol yap
        if chatService.isConnected {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.retryAllPendingMessages()
            }
        }
    }
    
    /// Tüm pending/failed mesajları yeniden gönder.
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
                    clientId: item.id
                )
                
                // .sent olarak işaretle — tekrar gönderilmesini önle.
                // isConnected guard'ı socket'in bağlı olduğunu doğruluyor.
                item.status = .sent
            }
            
            try modelContext.save()
            print("✅ Retry complete: \(pendingMessages.count) messages marked as sent")
        } catch {
            print("❌ App-wide retry error: \(error.localizedDescription)")
        }
    }
}
