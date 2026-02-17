//
//  DependencyContainer.swift
//  SoniApp
//
//  Merkezi bağımlılık yönetimi. Tüm servisler burada yaratılır
//  ve ihtiyaç duyan sınıflara inject edilir.
//

import Foundation
import SwiftData
import Combine

/// Uygulama genelindeki tüm bağımlılıkları yöneten merkezi container.
///
/// **Neden `@MainActor` YOK?**
/// `@MainActor` tüm property'leri actor-isolated yapar.
/// SwiftUI'nin `@StateObject` property wrapper'ı, dynamic member lookup
/// ile property'lere erişir. Actor isolation bu mekanizmayı bozar:
///   - `container.isAuthenticated` → actor-isolated property
///   - SwiftUI → `ObservedObject.Wrapper.subscript(dynamicMember:)` dener
///   - Sonuç: `Binding<Bool>` döner, `Bool` değil → compile hatası
///
/// SwiftUI View'ları zaten `@MainActor` üzerinde çalışır.
/// Container'ın da `@MainActor` olmasına gerek yok.
final class DependencyContainer: ObservableObject {
    
    // MARK: - Forwarded Published Property
    
    /// **Nested ObservableObject Problemi ve Çözümü:**
    ///
    /// SwiftUI `@StateObject`/`@ObservedObject` sadece kendi objesinin
    /// `@Published` property'lerini dinler. İç içe geçmiş ObservableObject'lerin
    /// değişikliklerini otomatik izlemez.
    ///
    /// Örnek:
    /// ```swift
    /// // BU ÇALIŞMAZ — View güncellenmez:
    /// if container.sessionStore.isAuthenticated { ... }
    ///
    /// // BU ÇALIŞIR — container'ın kendi @Published'ı:
    /// if container.isAuthenticated { ... }
    /// ```
    ///
    /// Combine ile `sessionStore.$isAuthenticated` → `self.$isAuthenticated` forward ediliyor.
    @Published var isAuthenticated: Bool = false
    
    // MARK: - Shared Services (App-scoped)
    
    /// Oturum bilgileri store'u
    let sessionStore: SessionStore
    
    /// Push notification token servisi
    let pushNotificationService: PushNotificationServiceProtocol
    
    /// Socket.io chat servisi
    let chatService: SocketChatService
    
    // MARK: - Private
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Init
    
    init() {
        self.sessionStore = SessionStore()
        self.pushNotificationService = PushNotificationService()
        self.chatService = SocketChatService()
        
        // Başlangıç değerini senkronize et
        self.isAuthenticated = sessionStore.isAuthenticated
        
        // SessionStore'un isAuthenticated değişikliğini container'a forward et.
        // `assign(to:)` — Combine'ın publisher'ı doğrudan @Published property'ye
        // bağlayan operatörü. Subscription, @Published property yaşadığı sürece devam eder.
        // Ayrı bir `AnyCancellable` tutmaya gerek yok — `assign(to: &$prop)` bunu otomatik yapar.
        sessionStore.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .assign(to: &$isAuthenticated)
        
        // SessionStore'un HER değişikliğini (unreadCounts dahil) container'a forward et.
        // Bu sayede ChatListView, sessionStore.unreadCounts değiştiğinde re-render olur.
        // Nested ObservableObject problemi: SwiftUI sadece container'ın @Published'larını izler,
        // sessionStore'un değişikliklerini görmez — bu forward bunu çözer.
        sessionStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // Socket bağlantısını başlat
        self.chatService.connect()
        
        // Uygulama yeniden açıldığında push token'ı server'a gönder
        // (Kullanıcı zaten login'se — token APNs'den gelmiş olabilir)
        sendPushTokenOnStartupIfNeeded()
    }
    
    /// App restart sonrası push token'ı server'a gönder.
    /// Login sırasında da gönderilir ama app kill+restart senaryosunda
    /// bu metod catch-all görevi görür.
    private func sendPushTokenOnStartupIfNeeded() {
        guard let token = sessionStore.deviceToken,
              let username = sessionStore.currentUsername,
              sessionStore.isAuthenticated else { return }
        
        pushNotificationService.saveDeviceToken(username: username, token: token) { success in
            if success {
                print("✅ Push token sent on app startup")
            }
        }
    }
    
    // MARK: - Factory Methods
    
    /// Auth işlemleri için servis yaratır.
    /// Her çağrıda yeni instance döner (value semantics gibi davranır).
    func makeAuthService() -> AuthService {
        return AuthService(
            sessionStore: sessionStore,
            pushNotificationService: pushNotificationService
        )
    }
}
