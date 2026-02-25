//  SoniApp
import Foundation

extension Date {
    
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    static func fromISO8601(_ string: String) -> Date? {
        return iso8601Formatter.date(from: string)
    }
    
    var iso8601String: String {
        return Date.iso8601Formatter.string(from: self)
    }
}
