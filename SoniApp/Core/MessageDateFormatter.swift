//
//  MessageDateFormatter.swift
//  SoniApp
//
//  Mesaj tarihlerini kullanıcı dostu string'lere çevirir.
//  WhatsApp tarzı: "Today", "Yesterday", "Monday", "Feb 6th" + "17:30"
//

import Foundation

/// Mesaj tarihlerini formatting eden yardımcı.
///
/// **Neden ayrı bir sınıf?**
/// Bu mantık View'da veya ViewModel'de olmamalı.
/// Birden fazla yerde kullanılabilir (ChatView, MessageInfoView).
/// Formatter instance'ları pahalıdır — burada static olarak cache'leniyor.
enum MessageDateFormatter {
    
    // MARK: - Cached Formatters
    
    /// Saat:dakika formatı — "17:30", "6:03"
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    
    /// Gün adı — "Monday", "Tuesday"
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        f.locale = Locale(identifier: "en_US")
        return f
    }()
    
    /// Kısa tarih — "Feb 6th" benzeri
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.locale = Locale(identifier: "en_US")
        return f
    }()
    
    // MARK: - Public API
    
    /// Mesaj balonunun altında gösterilecek saat.
    /// Örnek: "17:30"
    static func timeString(from date: Date) -> String {
        return timeFormatter.string(from: date)
    }
    
    /// Gün değişiminde gösterilecek separator text.
    /// Örnek: "Today", "Yesterday", "Monday", "Feb 6"
    ///
    /// **Mantık:**
    /// ```
    /// bugün       → "Today"
    /// dün         → "Yesterday"
    /// bu hafta    → "Monday", "Tuesday"... (gün adı)
    /// daha eski   → "Feb 6"
    /// ```
    ///
    /// Bu hesaplama her render'da yapılır (dinamik).
    /// Yani dün "Feb 15" olan şey bugün otomatik "Yesterday" olur.
    static func daySeparatorString(from date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return "Today"
        }
        
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        
        // Bu hafta içinde mi? (son 7 gün)
        if let weekAgo = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)),
           date >= weekAgo {
            return weekdayFormatter.string(from: date)
        }
        
        // Daha eski — "Feb 6" formatı
        // Farklı yılsa yılı da ekle
        if !calendar.isDate(date, equalTo: now, toGranularity: .year) {
            let yearFormatter = DateFormatter()
            yearFormatter.dateFormat = "MMM d, yyyy"
            yearFormatter.locale = Locale(identifier: "en_US")
            return yearFormatter.string(from: date)
        }
        
        return shortDateFormatter.string(from: date)
    }
    
    /// İki tarih aynı gün mü? Date separator gösterme kararı için.
    static func isSameDay(_ date1: Date, _ date2: Date) -> Bool {
        return Calendar.current.isDate(date1, inSameDayAs: date2)
    }
}
