//
//  DependencyContainer.swift
//  SoniApp
//

import Foundation
import SwiftData
import Combine

final class DependencyContainer: ObservableObject {
    
    /// Forwarded from SessionStore (nested ObservableObject won't trigger SwiftUI updates)
    @Published var isAuthenticated: Bool = false
    
    // MARK: - Shared Services
    let sessionStore: SessionStore
    let pushNotificationService: PushNotificationServiceProtocol
    let voipPushService: VoIPPushServiceProtocol
    let chatService: SocketChatService
    let retryService: PendingMessageRetryService
    let callManager: CallManager
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Init
    
    init() {
        self.sessionStore = SessionStore()
        self.pushNotificationService = PushNotificationService()
        self.voipPushService = VoIPPushService()
        self.chatService = SocketChatService()
        self.retryService = PendingMessageRetryService(chatService: chatService, sessionStore: sessionStore)
        self.callManager = CallManager(chatService: chatService)
        
        self.isAuthenticated = sessionStore.isAuthenticated
        
        // Forward auth state changes
        sessionStore.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .assign(to: &$isAuthenticated)
        
        // Forward all SessionStore changes for SwiftUI re-renders
        sessionStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        self.voipPushService.registerForVoIP()
        
        self.voipPushService.onIncomingPush = { [weak self] payload, completion in
            self?.callManager.handleVoIPPush(payload: payload, completion: completion)
        }
        
        self.chatService.connect()
        
        sendPushTokenOnStartupIfNeeded()
    }
    
    /// Send push token on app restart if user is already logged in.
    private func sendPushTokenOnStartupIfNeeded() {
        // Read fresh from UserDefaults — token might have arrived after SessionStore init
        let token = UserDefaults.standard.string(forKey: "deviceToken") ?? sessionStore.deviceToken
        guard let token = token, !token.isEmpty,
              let username = sessionStore.currentUsername,
              sessionStore.isAuthenticated else { return }
        
        pushNotificationService.saveDeviceToken(username: username, token: token) { success in
            if success {
                print("✅ Push token sent on app startup")
            }
        }
    }
    
    // MARK: - Factory
    
    func makeAuthService() -> AuthService {
        return AuthService(
            sessionStore: sessionStore,
            pushNotificationService: pushNotificationService,
            voipPushService: voipPushService
        )
    }
}
