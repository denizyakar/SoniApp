//  SoniApp
//  WhatsApp style: "Today", "Yesterday", "Monday", "Feb 6th" + "17:30"
//

import Foundation

enum MessageDateFormatter {
    
    // MARK: - Cached Formatters
    
    /// Hour:minute format — "17:30", "6:03"
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    
    /// Day name — "Monday", "Tuesday"
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        f.locale = Locale(identifier: "en_US")
        return f
    }()
    
    /// Short date — "Feb 6" format
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.locale = Locale(identifier: "en_US")
        return f
    }()
    
    static func timeString(from date: Date) -> String {
        return timeFormatter.string(from: date)
    }
    
    static func daySeparatorString(from date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return "Today"
        }
        
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        
        // Within this week? (last 7 days)
        if let weekAgo = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)),
           date >= weekAgo {
            return weekdayFormatter.string(from: date)
        }
        
        // Older — "Feb 6" format
        // Include year if different year
        if !calendar.isDate(date, equalTo: now, toGranularity: .year) {
            let yearFormatter = DateFormatter()
            yearFormatter.dateFormat = "MMM d, yyyy"
            yearFormatter.locale = Locale(identifier: "en_US")
            return yearFormatter.string(from: date)
        }
        
        return shortDateFormatter.string(from: date)
    }
    
    /// Are two dates on the same day? Used for date separator decisions.
    static func isSameDay(_ date1: Date, _ date2: Date) -> Bool {
        return Calendar.current.isDate(date1, inSameDayAs: date2)
    }
}
