//
//  MessageStatus.swift
//  SoniApp
//
//  Mesaj durumlarını tanımlayan enum.
//  SwiftData raw String olarak saklar.
//

import Foundation

/// Mesajın gönderim durumu.
///
/// **Akış:**
/// ```
/// pending → sent (başarılı)
/// pending → failed (başarısız)
/// failed  → pending (retry)
/// sent    → read (okundu)
/// ```
enum MessageStatus: String {
    /// Henüz gönderilmedi — lokal kaydedildi, socket ile gönderilmeyi bekliyor
    case pending
    
    /// Başarıyla gönderildi — server'a ulaştı
    case sent
    
    /// Gönderilemedi — internet yok veya bağlantı hatası
    case failed
}
