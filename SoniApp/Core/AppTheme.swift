import SwiftUI

enum AppTheme {
    
    static let primary = Color(red: 0.12, green: 0.25, blue: 0.69)
    
    /// solid
    static let black = Color.black
    
    static let white = Color.white

    static let primaryLight = primary.opacity(0.15)
    
    static let primaryMuted = primary.opacity(0.5)
    
    static let primarySubtle = primary.opacity(0.08)
    
    /// bg
    static let background = Color(red: 0.08, green: 0.15, blue: 0.42)
    
    /// Slightly lighter blue — cards, list rows, input fields
    static let backgroundLight = Color(red: 0.12, green: 0.22, blue: 0.52)
    
    //func
    
    static let myBubble = Color(red: 0.18, green: 0.35, blue: 0.75)
    
    static let incomingBubble = Color(red: 0.14, green: 0.26, blue: 0.58)
    
    static let inputBorder = white.opacity(0.25)
    
    static let secondaryText = white.opacity(0.7)
    
    static let dateBadge = white.opacity(0.12)
}
