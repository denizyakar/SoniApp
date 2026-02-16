//
//  Message.swift
//  SoniApp
//
//  DEĞİŞTİRİLDİ: AuthManager.shared bağımlılığı kaldırıldı.
//

import Foundation

/// Network'ten gelen mesaj verisi (DTO — Data Transfer Object).
///
/// **Ne değişti?**
/// Eski `isFromCurrentUser` property'si `AuthManager.shared.currentUserId`'ye
/// bağımlıydı. Bir DATA modeli, global bir singleton'ın state'ine bağlı olmamalı.
///
/// **Neden?**
/// Model struct'ları "saf veri taşıyıcıları"dır (pure data carriers).
/// Dış dünya hakkında bilgi sahibi olmamalıdırlar.
/// `isFromCurrentUser` kararını View veya ViewModel vermeli — Model değil.
///
/// `isFromCurrentUser` artık `MessageItem` (SwiftData entity) üzerinde
/// parametre alarak hesaplanıyor.
struct Message: Identifiable, Codable {
    let id: String
    let text: String
    let senderId: String
    let receiverId: String
    let date: String?
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case text
        case senderId
        case receiverId
        case date
    }
}
