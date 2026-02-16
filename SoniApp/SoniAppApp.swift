//
//  SoniAppApp.swift
//  SoniApp
//
//  DEĞİŞTİRİLDİ: DependencyContainer entegrasyonu.
//

import SwiftUI
import SwiftData

/// Uygulama giriş noktası.
///
/// **Ne değişti?**
/// ```swift
/// // ESKİ:
/// @ObservedObject var authManager = AuthManager.shared   // ← Singleton
/// SocketChatService.shared.connect()                      // ← Başka bir singleton
/// ```
///
/// **Yeni yaklaşım:**
/// `DependencyContainer` tüm servisleri yaratır ve yönetir.
/// `@EnvironmentObject` ile View hiyerarşisine inject edilir.
/// Böylece her View, container'dan ihtiyacı olan servise erişebilir.
@main
struct ChatAppApp: App {
    
    /// Merkezi bağımlılık container'ı — uygulama boyunca yaşar.
    @StateObject private var container = DependencyContainer()
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Not: Socket bağlantısı DependencyContainer'dan başlatılıyor
    }
    
    var body: some Scene {
        WindowGroup {
            /// **Neden `container.isAuthenticated`?**
            /// SwiftUI nested ObservableObject'leri otomatik izlemez.
            /// `container.sessionStore.isAuthenticated` değişse bile View güncellenmez.
            /// Bu yüzden DependencyContainer, SessionStore'un değerini
            /// Combine ile kendi @Published property'sine forward ediyor.
            if container.isAuthenticated {
                ChatListView()
                    .environmentObject(container)
            } else {
                AuthView()
                    .environmentObject(container)
            }
        }
        .modelContainer(for: [MessageItem.self, UserItem.self])
    }
}
