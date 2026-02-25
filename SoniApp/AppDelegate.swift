//
//  AppDelegate.swift
//  SoniApp
//

import UIKit
import UserNotifications
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
        
        // Reset badge count on launch
        UNUserNotificationCenter.current().setBadgeCount(0)
        
        return true
    }
    
    // MARK: - Remote Notifications
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        
        print("📲 Device Token: \(token)")
        
        UserDefaults.standard.set(token, forKey: "deviceToken")
        
        let username = UserDefaults.standard.string(forKey: "username")
        if let username = username, !username.isEmpty {
            PushNotificationService().saveDeviceToken(username: username, token: token) { _ in }
        }
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        // Suppress push when ChatListView is visible
        let isInChatList = UserDefaults.standard.bool(forKey: "isInChatList")
        if isInChatList {
            print("🔕 User is in ChatListView, suppressing push")
            completionHandler([])
            return
        }
        
        let userInfo = notification.request.content.userInfo
        
        if let senderId = userInfo["senderIdFromPayload"] as? String {
            // Suppress if this chat is currently open
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
        let userInfo = response.notification.request.content.userInfo
        
        // Navigate to sender's chat on push tap
        if let senderId = userInfo["senderIdFromPayload"] as? String {
            UserDefaults.standard.set(senderId, forKey: "deepLinkUserId")
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .pushNotificationTapped,
                    object: nil,
                    userInfo: ["senderId": senderId]
                )
            }
        }
        
        completionHandler()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let pushNotificationTapped = Notification.Name("pushNotificationTapped")
}
