//
//  AppError.swift
//  SoniApp
//
//  Typed error hierarchy — replaces all silent `try?` failures
//  with explicit, debuggable error cases.
//

import Foundation

/// Uygulamanın tüm katmanlarında kullanılan merkezi hata enum'u.
///
/// **Neden var?**
/// Projede her yerde `try?` ile hatalar yutuluyordu. Bu enum sayesinde:
/// - Her hata türü açıkça tanımlı → debug kolaylaşır
/// - ViewModel'ler hatayı UI'a taşıyabilir → kullanıcı ne olduğunu bilir
/// - Gelecekte telemetri (Crashlytics vb.) eklendiğinde her hata loglanabilir
enum AppError: Error, LocalizedError {
    
    // MARK: - Network Errors
    case networkError(underlying: Error)
    case invalidURL(String)
    case invalidResponse(statusCode: Int)
    case serverError(message: String)
    
    // MARK: - Parse Errors
    case decodingError(underlying: Error)
    case invalidDateFormat(String)
    
    // MARK: - Storage Errors
    case persistenceError(underlying: Error)
    
    // MARK: - Auth Errors
    case notAuthenticated
    case tokenExpired
    
    // MARK: - Socket Errors
    case socketDisconnected
    case messageSendFailed
    
    /// Kullanıcıya gösterilebilecek açıklama
    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidResponse(let code):
            return "Server returned status \(code)"
        case .serverError(let message):
            return message
        case .decodingError(let error):
            return "Data parsing error: \(error.localizedDescription)"
        case .invalidDateFormat(let dateString):
            return "Invalid date format: \(dateString)"
        case .persistenceError(let error):
            return "Storage error: \(error.localizedDescription)"
        case .notAuthenticated:
            return "You are not logged in"
        case .tokenExpired:
            return "Session expired. Please log in again"
        case .socketDisconnected:
            return "Real-time connection lost"
        case .messageSendFailed:
            return "Message could not be sent"
        }
    }
}
