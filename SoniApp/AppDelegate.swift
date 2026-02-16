//
//  AppDelegate.swift
//  SoniApp
//
//  DEĞİŞTİRİLDİ: AuthManager.shared referansları kaldırıldı.
//

import UIKit
import UserNotifications

/// **Ne değişti?**
/// Eskiden `AuthManager.shared` doğrudan kullanılıyordu:
/// - `AuthManager.shared.setDeviceToken(token)` → Artık geçici olarak
///   UserDefaults'ta saklanıp DependencyContainer tarafından okunuyor
/// - `AuthManager.shared.currentChatPartnerId` → Container'daki SessionStore
///
/// **AppDelegate özel durumu:**
/// AppDelegate, UIKit lifecycle'ından geliyor — SwiftUI DI mekanizması
/// (@EnvironmentObject) burada çalışmaz. Bu yüzden:
/// 1. Device token'ı UserDefaults'a geçici kaydediyoruz
/// 2. Foreground notification filtresinde de UserDefaults okuyoruz
/// Bu bir pragmatik trade-off'tur — mükemmel değil ama çalışır.
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    // MARK: - App Lifecycle
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("✅ Notification permission granted.")
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            } else if let error = error {
                print("❌ Permission denied or error: \(error.localizedDescription)")
            }
        }
        
        return true
    }
    
    // MARK: - Remote Notifications
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        
        print("📲 Device Token: \(token)")
        
        // Token'ı UserDefaults'a kaydet — DependencyContainer bunu okuyacak
        UserDefaults.standard.set(token, forKey: "deviceToken")
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        let userInfo = notification.request.content.userInfo
        
        if let senderId = userInfo["senderIdFromPayload"] as? String {
            // Aktif chat partner kontrolü — UserDefaults üzerinden
            let currentPartnerId = UserDefaults.standard.string(forKey: "currentChatPartnerId")
            
            if currentPartnerId == senderId {
                print("🔕 Chat is open, don't send notification")
                completionHandler([])
                return
            }
        }
        
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
