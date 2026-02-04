//
//  AppDelegate.swift
//  SoniApp
//
//  Created by Ali Deniz Yakar on 4.02.2026.
//

import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    // MARK: - App Lifecycle
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        // Configure Notification Center
        let center = UNUserNotificationCenter.current()
        center.delegate = self // Important: Allows handling notifications while app is in foreground
        
        // Request Permission
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
    
    // Success: Device Token received
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Convert token to string
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        
        print("📲 Device Token: \(token)")
        
         AuthManager.shared.setDeviceToken(token)
    }
    
    // Failure: Could not get Device Token
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    // Handle notification when app is in FOREGROUND
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        let userInfo = notification.request.content.userInfo
        
        // Take sender ID in notification
        if let senderId = userInfo["senderIdFromPayload"] as? String {
            
            // Don't show notification if we are messaging with this user:
            if AuthManager.shared.currentChatPartnerId == senderId {
                print("🔕 Chat is open, don't send notification")
                completionHandler([]) // Empty array
                return
            }
        }
        
        // If not, send notification
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap (user clicked the banner)
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle deep linking or navigation here based on notification content
        completionHandler()
    }
}
