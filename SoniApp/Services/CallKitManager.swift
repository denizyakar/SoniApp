//
//  CallKitManager.swift
//  SoniApp
//

import Foundation
import CallKit
import AVFoundation
import WebRTC

/// Delegate for CallKit user actions.
protocol CallKitManagerDelegate: AnyObject {
    func callKitDidAnswerCall(uuid: UUID)
    func callKitDidEndCall(uuid: UUID)
}

final class CallKitManager: NSObject {
    
    // Managers
    private let provider: CXProvider
    private let callController = CXCallController()
    
    weak var delegate: CallKitManagerDelegate?
    
    override init() {
        let providerConfiguration = CXProviderConfiguration()
        providerConfiguration.supportsVideo = true
        providerConfiguration.maximumCallsPerCallGroup = 1
        providerConfiguration.supportedHandleTypes = [.generic]
        
        self.provider = CXProvider(configuration: providerConfiguration)
        
        super.init()
        
        self.provider.setDelegate(self, queue: nil)
    }
    
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    // MARK: - API
    
    func reportIncomingCall(uuid: UUID, callerName: String, hasVideo: Bool = true, completion: ((Error?) -> Void)? = nil) {
        if isSimulator {
            print("[CallKitManager] Simulator detected, bypassing CallKit incoming call UI.")
            completion?(nil)
            return
        }
        
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: callerName)
        update.hasVideo = hasVideo
        
        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            completion?(error)
        }
    }
    
    func answerCall(uuid: UUID) {
        if isSimulator { return }
        let answerCallAction = CXAnswerCallAction(call: uuid)
        let transaction = CXTransaction(action: answerCallAction)
        requestTransaction(transaction)
    }
    
    func startOutgoingCall(uuid: UUID, calleeName: String, hasVideo: Bool = true) {
        if isSimulator { return }
        
        let handle = CXHandle(type: .generic, value: calleeName)
        let startCallAction = CXStartCallAction(call: uuid, handle: handle)
        startCallAction.isVideo = hasVideo
        
        let transaction = CXTransaction(action: startCallAction)
        requestTransaction(transaction)
    }
    
    func reportCallConnected(uuid: UUID) {
        if isSimulator { return }
        provider.reportOutgoingCall(with: uuid, connectedAt: Date())
    }
    
    func endCall(uuid: UUID) {
        if isSimulator { return }
        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)
        requestTransaction(transaction)
    }
    
    private func requestTransaction(_ transaction: CXTransaction) {
        callController.request(transaction) { error in
            if let error = error {
                print("[CallKitManager] Error requesting transaction: \(error.localizedDescription)")
            } else {
                print("[CallKitManager] Requested transaction successfully")
            }
        }
    }
}

// MARK: - CXProviderDelegate

extension CallKitManager: CXProviderDelegate {
    
    func providerDidReset(_ provider: CXProvider) {}
    
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        delegate?.callKitDidAnswerCall(uuid: action.callUUID)
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        delegate?.callKitDidEndCall(uuid: action.callUUID)
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
        RTCAudioSession.sharedInstance().isAudioEnabled = true
    }
    
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
        RTCAudioSession.sharedInstance().isAudioEnabled = false
    }
}
