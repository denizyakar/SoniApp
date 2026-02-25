import Foundation
import Combine
import WebRTC
import UIKit

final class CallManager: ObservableObject {
    @Published var isCallActive: Bool = false
    @Published var incomingCallData: [String: Any]? = nil
    
    @Published var connectionState: RTCIceConnectionState = .new
    @Published var localVideoTrack: RTCVideoTrack?
    @Published var remoteVideoTrack: RTCVideoTrack?
    @Published var isCameraOff: Bool = false
    @Published var isMuted: Bool = false
    @Published var isSpeakerOn: Bool = true
    @Published var isRemoteCameraOff: Bool = false
    
    private let chatService: SocketChatService
    private var webRTCClient: WebRTCClient?
    private var cancellables = Set<AnyCancellable>()
    private let callKitManager = CallKitManager()
    private var activeCallUUID: UUID?
    var currentOpponentId: String?
    
    @Published var outgoingOpponentName: String?
    @Published var outgoingOpponentAvatarUrl: String?
    
    init(chatService: SocketChatService) {
        self.chatService = chatService
        self.setupSubscriptions()
        self.setupLifecycleObservers()
        self.callKitManager.delegate = self
    }
    
    private func setupLifecycleObservers() {
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.handleAppDidEnterBackground()
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.handleAppWillEnterForeground()
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] notification in
                self?.handleAudioRouteChange(notification: notification)
            }
            .store(in: &cancellables)
    }
    
    private func setupSubscriptions() {
        chatService.incomingCallPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.handleIncomingCall(data: data)
            }
            .store(in: &cancellables)
            
        chatService.callAnsweredPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.handleCallAnswered(data: data)
            }
            .store(in: &cancellables)
            
        chatService.iceCandidatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.handleRemoteIceCandidate(data: data)
            }
            .store(in: &cancellables)
            
        chatService.callEndedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.handleCallEnded(data: data)
            }
            .store(in: &cancellables)
            
        chatService.cameraToggledPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                guard let isOff = data["isOff"] as? Bool else { return }
                self?.isRemoteCameraOff = isOff
            }
            .store(in: &cancellables)
    }
    
    @Published var hasAnsweredCall: Bool = false
    private var hasReceivedRemoteSdp: Bool = false
    private var pendingRemoteCandidates: [RTCIceCandidate] = []
    
    // MARK: - Incoming Call
    
    private func handleIncomingCall(data: [String: Any]) {
        print("[CallManager] Incoming call from Socket")
        
        let callerId = data["callerId"] as? String
        
        if isCallActive, currentOpponentId == callerId {
            print("[CallManager] Call already active via VoIP push, updating data only.")
            self.incomingCallData = data
            return
        }
        
        incomingCallData = data
        currentOpponentId = callerId
        hasAnsweredCall = false
        hasReceivedRemoteSdp = false
        pendingRemoteCandidates.removeAll()
        
        let callerName = data["callerName"] as? String ?? "Bilinmeyen"
        let uuid = UUID()
        self.activeCallUUID = uuid
        
        callKitManager.reportIncomingCall(uuid: uuid, callerName: callerName, hasVideo: true) { error in
            if let error = error {
                print("[CallKit] Error reporting socket incoming call: \(error.localizedDescription)")
            }
        }
        
        isCallActive = true
    }
    
    func handleVoIPPush(payload: [String: Any], completion: @escaping () -> Void) {
        let callerName = payload["callerName"] as? String ?? "Bilinmeyen"
        let callerId = payload["callerId"] as? String
        
        if isCallActive, self.currentOpponentId == callerId {
            print("[CallManager] Already active call, ignoring VoIP push.")
            completion()
            return
        }
        
        self.incomingCallData = [
            "callerId": callerId ?? "",
            "callerName": callerName,
            "callerAvatarUrl": payload["callerAvatarUrl"] ?? ""
        ]
        self.currentOpponentId = callerId
        self.hasAnsweredCall = false
        self.hasReceivedRemoteSdp = false
        self.pendingRemoteCandidates.removeAll()
        
        let uuidString = payload["callUUID"] as? String ?? UUID().uuidString
        let uuid = UUID(uuidString: uuidString) ?? UUID()
        self.activeCallUUID = uuid
        
        callKitManager.reportIncomingCall(uuid: uuid, callerName: callerName, hasVideo: true) { error in
            DispatchQueue.main.async {
                self.isCallActive = true
            }
            completion()
        }
    }
    
    private func handleCallAnswered(data: [String: Any]) {
        print("[CallManager] Call answered by remote")
        
        if let uuid = self.activeCallUUID {
            self.callKitManager.reportCallConnected(uuid: uuid)
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.hasAnsweredCall = true
        }
        
        guard let answerDict = data["answer"] as? [String: Any],
              let sdp = answerDict["sdp"] as? String,
              let typeString = answerDict["type"] as? String else { return }
        
        let type: RTCSdpType = typeString == "answer" ? .answer : (typeString == "offer" ? .offer : .prAnswer)
        let remoteSdp = RTCSessionDescription(type: type, sdp: sdp)
        
        webRTCClient?.set(remoteSdp: remoteSdp) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[CallManager] Error setting remote SDP: \(error)")
                } else {
                    print("[CallManager] Remote SDP set successfully")
                    self?.hasReceivedRemoteSdp = true
                    self?.processPendingCandidates()
                }
            }
        }
    }
    
    private func handleRemoteIceCandidate(data: [String: Any]) {
        guard let candidateDict = data["candidate"] as? [String: Any],
              let sdp = candidateDict["candidate"] as? String,
              let sdpMid = candidateDict["sdpMid"] as? String,
              let sdpMLineIndex = candidateDict["sdpMLineIndex"] as? Int32 else { return }
        
        let candidate = RTCIceCandidate(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
        
        if hasReceivedRemoteSdp {
            webRTCClient?.set(remoteCandidate: candidate)
        } else {
            print("[CallManager] Queuing remote ICE Candidate because SDP is not set yet.")
            pendingRemoteCandidates.append(candidate)
        }
    }
    
    private func processPendingCandidates() {
        print("[CallManager] Processing \(pendingRemoteCandidates.count) pending ICE candidates.")
        for candidate in pendingRemoteCandidates {
            webRTCClient?.set(remoteCandidate: candidate)
        }
        pendingRemoteCandidates.removeAll()
    }
    
    private func handleCallEnded(data: [String: Any]) {
        print("[CallManager] Call ended by remote")
        cleanup()
    }
    
    // MARK: - App Lifecycle
    private func handleAppDidEnterBackground() {
        guard isCallActive, let opponentId = currentOpponentId else { return }
        if !isCameraOff {
            localVideoTrack?.isEnabled = false
            chatService.emitCameraToggled(isOff: true, to: opponentId)
        }
    }
    
    private func handleAppWillEnterForeground() {
        guard isCallActive, let opponentId = currentOpponentId else { return }
        if !isCameraOff {
            localVideoTrack?.isEnabled = true
            chatService.emitCameraToggled(isOff: false, to: opponentId)
        }
    }
    
    private func handleAudioRouteChange(notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            let currentRoute = AVAudioSession.sharedInstance().currentRoute
            let isSpeakerRoute = currentRoute.outputs.contains(where: { $0.portType == .builtInSpeaker })
            self?.isSpeakerOn = isSpeakerRoute
        }
    }
    
    // MARK: - WebRTC Setup
    private func setupWebRTC() {
        webRTCClient?.close()
        
        let client = WebRTCClient()
        client.delegate = self
        self.webRTCClient = client
        
        self.localVideoTrack = client.localVideoTrack
        self.isCameraOff = false
        self.isMuted = false
        self.isSpeakerOn = true
        client.setAudioRoute(toSpeaker: true)
    }
    
    // MARK: - Actions
    
    func startCall(to opponentId: String, callerId: String, callerName: String, callerAvatar: String, calleeName: String, calleeAvatar: String) {
        currentOpponentId = opponentId
        outgoingOpponentName = calleeName
        outgoingOpponentAvatarUrl = calleeAvatar
        
        isCallActive = true
        hasAnsweredCall = false
        hasReceivedRemoteSdp = false
        connectionState = .new
        
        let uuid = UUID()
        self.activeCallUUID = uuid
        callKitManager.startOutgoingCall(uuid: uuid, calleeName: calleeName, hasVideo: true)
        pendingRemoteCandidates.removeAll()
        
        setupWebRTC()
        
        webRTCClient?.offer { [weak self] sdp in
            let offerDict: [String: Any] = [
                "type": "offer",
                "sdp": sdp.sdp
            ]
            let data: [String: Any] = [
                "offer": offerDict,
                "to": opponentId,
                "callerId": callerId,
                "callerName": callerName,
                "callerAvatarUrl": callerAvatar
            ]
            self?.chatService.emitCallUser(data: data)
        }
    }
    
    func acceptCall() {
        if hasAnsweredCall { return }
        
        guard let data = incomingCallData,
              let offerDict = data["offer"] as? [String: Any],
              let opponentId = data["callerId"] as? String,
              let sdp = offerDict["sdp"] as? String,
              let typeString = offerDict["type"] as? String else { return }
        
        let type: RTCSdpType = typeString == "offer" ? .offer : .answer
        let remoteSdp = RTCSessionDescription(type: type, sdp: sdp)
        
        currentOpponentId = opponentId
        hasAnsweredCall = true
        connectionState = .new
        
        if let uuid = activeCallUUID {
            callKitManager.answerCall(uuid: uuid)
        }
        
        // Small delay to prevent UI freeze during WebRTC hardware setup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.setupWebRTC()
            
            self.webRTCClient?.set(remoteSdp: remoteSdp) { error in
                print("[CallManager] Set remote SDP for incoming call")
                DispatchQueue.main.async {
                    self.hasReceivedRemoteSdp = true
                    self.processPendingCandidates()
                }
                
                self.webRTCClient?.answer { answerSdp in
                    let answerDict: [String: Any] = [
                        "type": "answer",
                        "sdp": answerSdp.sdp
                    ]
                    let emitData: [String: Any] = [
                        "answer": answerDict,
                        "to": opponentId
                    ]
                    self.chatService.emitAnswerCall(data: emitData)
                }
            }
        }
        
    }
    
    func endCall() {
        if let opponentId = currentOpponentId {
            chatService.emitEndCall(to: opponentId)
        }
        cleanup()
    }
    
    private func cleanup() {
        DispatchQueue.main.async {
            self.isCallActive = false
            self.incomingCallData = nil
            self.currentOpponentId = nil
            self.outgoingOpponentName = nil
            self.outgoingOpponentAvatarUrl = nil
            self.remoteVideoTrack = nil
            self.localVideoTrack = nil
            self.connectionState = .new
            self.hasAnsweredCall = false
            self.hasReceivedRemoteSdp = false
            self.isRemoteCameraOff = false
        }
        
        if let uuid = activeCallUUID {
            callKitManager.endCall(uuid: uuid)
            activeCallUUID = nil
        }
        
        webRTCClient?.close()
        webRTCClient = nil
    }
    
    // MARK: - Toggles
    func toggleMute() {
        isMuted.toggle()
        webRTCClient?.setAudioEnabled(!isMuted)
    }
    
    func toggleCamera() {
        isCameraOff.toggle()
        localVideoTrack?.isEnabled = !isCameraOff
        if let opponentId = currentOpponentId {
            chatService.emitCameraToggled(isOff: isCameraOff, to: opponentId)
        }
    }
    
    func switchCamera() {
        webRTCClient?.switchCamera()
    }
    
    func toggleSpeaker() {
        isSpeakerOn.toggle()
        webRTCClient?.setAudioRoute(toSpeaker: isSpeakerOn)
    }
}

extension CallManager: WebRTCClientDelegate {
    func webRTCClient(_ client: WebRTCClient, didDiscoverLocalCandidate candidate: RTCIceCandidate) {
        guard let toId = currentOpponentId else { return }
        let candidateDict: [String: Any] = [
            "candidate": candidate.sdp,
            "sdpMid": candidate.sdpMid ?? "",
            "sdpMLineIndex": candidate.sdpMLineIndex
        ]
        let data: [String: Any] = [
            "candidate": candidateDict,
            "to": toId
        ]
        chatService.emitIceCandidate(data: data)
    }
    
    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCIceConnectionState) {
        DispatchQueue.main.async {
            self.connectionState = state
        }
    }
    
    func webRTCClient(_ client: WebRTCClient, didReceiveData data: Data) {}
    
    func webRTCClient(_ client: WebRTCClient, didReceiveRemoteVideoTrack track: RTCVideoTrack) {
        DispatchQueue.main.async {
            self.remoteVideoTrack = track
        }
    }
}


// MARK: - CallKitManagerDelegate
extension CallManager: CallKitManagerDelegate {
    func callKitDidAnswerCall(uuid: UUID) {
        DispatchQueue.main.async { [weak self] in
            self?.acceptCall()
        }
    }
    
    func callKitDidEndCall(uuid: UUID) {
        DispatchQueue.main.async { [weak self] in
            // Nil first to prevent endCall → cleanup → callKitManager.endCall loop
            self?.activeCallUUID = nil
            if self?.isCallActive == true {
                self?.endCall()
            }
        }
    }
}
