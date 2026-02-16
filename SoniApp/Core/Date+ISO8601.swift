//
//  Date+ISO8601.swift
//  SoniApp
//
//  Statik ISO8601 tarih formatter.
//

import Foundation

/// Date ↔ String dönüşümleri için statik formatter.
///
/// **Neden var?**
/// `ChatViewModel.saveMessageToDB()` içinde HER mesaj kaydedildiğinde
/// yeni bir `ISO8601DateFormatter()` yaratılıyordu:
///
/// ```swift
/// let formatter = ISO8601DateFormatter()  // ← Her çağrıda yeni instance
/// formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
/// ```
///
/// `DateFormatter` ve `ISO8601DateFormatter` oluşturmak **pahalı** bir işlemdir.
/// Apple'ın kendi dökümantasyonunda "cache your formatters" diye yazılır.
/// 100 mesaj yüklendiğinde 100 formatter yaratmak yerine, tek bir statik
/// instance kullanmak hem bellek hem CPU açısından verimlidir.
extension Date {
    
    /// MongoDB'nin gönderdiği ISO8601 formatındaki string'leri parse eder.
    /// Örnek giriş: "2026-02-16T14:30:00.000Z"
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    /// ISO8601 string'den Date oluşturur. Parse edilemezse `nil` döner.
    static func fromISO8601(_ string: String) -> Date? {
        return iso8601Formatter.date(from: string)
    }
    
    /// Date'i ISO8601 string'e çevirir.
    var iso8601String: String {
        return Date.iso8601Formatter.string(from: self)
    }
}
