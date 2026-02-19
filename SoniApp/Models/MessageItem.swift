//
//  MessageItem.swift
//  SoniApp
//
//  DEĞİŞTİRİLDİ: AuthManager.shared bağımlılığı kaldırıldı.
//

import Foundation
import SwiftData

/// Lokal SwiftData entity — mesajların kalıcı (persistent) hali.
///
/// **Ne değişti?**
/// ```swift
/// // ESKİ (SORUNLU):
/// @Transient
/// var isFromCurrentUser: Bool {
///     return senderId == AuthManager.shared.currentUserId // ← Singleton bağımlılığı!
/// }
/// ```
///
/// **Neden sorunluydu?**
/// 1. Bir SwiftData @Model sınıfı, global bir singleton'a bağımlıydı
/// 2. Unit test'te `AuthManager.shared` mock'lanamaz
/// 3. SwiftData `@Transient` property'leri bazen beklenmeyen davranış gösterir
///
/// **Yeni yaklaşım:**
/// `isFromCurrentUser(userId:)` artık bir METOD.
/// `currentUserId` dışarıdan parametre olarak geçiliyor.
/// Model, kimin giriş yaptığını bilmiyor — sadece karşılaştırma yapıyor.
@Model
class MessageItem {
    @Attribute(.unique) var id: String
    var text: String
    var senderId: String
    var receiverId: String
    var date: Date
    var senderName: String
    var isRead: Bool
    var readAt: Date?
    var statusRaw: String  // MessageStatus raw value — SwiftData enum desteği sınırlı
    var imageUrl: String? // YENİ: Mesaj görseli
    
    /// Type-safe status erişimi
    @Transient
    var status: MessageStatus {
        get { MessageStatus(rawValue: statusRaw) ?? .sent }
        set { statusRaw = newValue.rawValue }
    }
    
    init(id: String, text: String, senderId: String, receiverId: String, date: Date, senderName: String = "", isRead: Bool = false, readAt: Date? = nil, status: MessageStatus = .sent, imageUrl: String? = nil) {
        self.id = id
        self.text = text
        self.senderId = senderId
        self.receiverId = receiverId
        self.date = date
        self.senderName = senderName
        self.isRead = isRead
        self.readAt = readAt
        self.statusRaw = status.rawValue
        self.imageUrl = imageUrl
    }
    
    /// Mesajın mevcut kullanıcıya ait olup olmadığını kontrol eder.
    ///
    /// **Parametre olarak alma kararı:**
    /// Eskiden `AuthManager.shared.currentUserId` doğrudan okunuyordu.
    /// Şimdi `userId` dışarıdan geçiliyor → model DI-friendly, test edilebilir.
    func isFromCurrentUser(userId: String?) -> Bool {
        return senderId == userId
    }
}
