import Foundation
import Combine
import WebRTC
import UIKit

final class CallManager: ObservableObject {
    
    enum CallPhase: Equatable {
        case idle
        case outgoingRinging
        case incomingRinging
        case connecting
        case active
        case ended
        case failed(reason: String)
        
        var isInCall: Bool {
            switch self {
            case .idle, .ended, .failed: return false
            default: return true
            }
        }
        
        var shouldShowCallScreen: Bool {
            switch self {
            case .idle, .ended: return false
            default: return true
            }
        }
    }
    
    @Published var callPhase: CallPhase = .idle
    @Published var incomingCallData: [String: Any]? = nil
    
    @Published var connectionState: RTCIceConnectionState = .new
    @Published var localVideoTrack: RTCVideoTrack?
    @Published var remoteVideoTrack: RTCVideoTrack?
    @Published var isCameraOff: Bool = false
    @Published var isMuted: Bool = false
    @Published var isSpeakerOn: Bool = true
    @Published var isRemoteCameraOff: Bool = false
    
    @Published var outgoingOpponentName: String?
    @Published var outgoingOpponentAvatarUrl: String?
    
    var currentOpponentId: String?
    var myUserId: String?
    
    private let chatService: SocketChatService
    private var webRTCClient: WebRTCClient?
    private var cancellables = Set<AnyCancellable>()
    private let callKitManager = CallKitManager()
    private var activeCallUUID: UUID?
    
    private var hasReceivedRemoteSdp: Bool = false
    private var pendingRemoteCandidates: [RTCIceCandidate] = []
    private var pendingAccept: Bool = false
    
    private var offerRetryTimer: Timer?
    private var ringTimeoutTimer: Timer?
    private var iceRecoveryTimer: Timer?
    
    init(chatService: SocketChatService) {
        self.chatService = chatService
        self.callKitManager.delegate = self
        self.callKitManager.setup()
        self.setupSubscriptions()
        self.setupLifecycleObservers()
    }
    
    func phaseString(_ phase: CallPhase) -> String {
        switch phase {
        case .idle: return "idle"
        case .outgoingRinging: return "outgoingRinging"
        case .incomingRinging: return "incomingRinging"
        case .connecting: return "connecting"
        case .active: return "active"
        case .ended: return "ended"
        case .failed(let r): return "failed(\(r))"
        }
    }
    
    private func transitionTo(_ newPhase: CallPhase) {
        print("[CALL] Phase: \(phaseString(callPhase)) → \(phaseString(newPhase))")
        callPhase = newPhase
        if !newPhase.isInCall {
            stopTimers()
        }
    }
    
    private func startOfferRetry(data: [String: Any]) {
        offerRetryTimer?.invalidate()
        offerRetryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, self.callPhase == .outgoingRinging else {
                self?.offerRetryTimer?.invalidate()
                return
            }
            print("[CALL] Retrying offer emit...")
            self.chatService.emitCallUser(data: data)
        }
    }
    
    private func startRingTimeout() {
        ringTimeoutTimer?.invalidate()
        ringTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            print("[CALL] Ringing timed out!")
            if self.callPhase == .outgoingRinging || self.callPhase == .incomingRinging {
                self.transitionTo(.failed(reason: "No answer"))
                self.doCleanup(sendEndToRemote: true)
            }
        }
    }
    
    private func stopTimers() {
        offerRetryTimer?.invalidate()
        ringTimeoutTimer?.invalidate()
        iceRecoveryTimer?.invalidate()
    }
    
    private func setupLifecycleObservers() {
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.handleAppDidEnterBackground() }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.handleAppWillEnterForeground() }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] notification in self?.handleAudioRouteChange(notification: notification) }
            .store(in: &cancellables)
    }
    
    private func setupSubscriptions() {
        chatService.connectionStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                guard let self = self else { return }
                if isConnected {
                    print("[CALL] Socket reconnected.")
                } else if self.callPhase.isInCall {
                    print("[CALL] Socket disconnected while in call! (Ignored, waiting for WebRTC ICE or 30s timeout)")
                }
            }
            .store(in: &cancellables)
            
        chatService.incomingCallPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in self?.handleIncomingCall(data: data) }
            .store(in: &cancellables)
            
        chatService.callAnsweredPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in self?.handleCallAnswered(data: data) }
            .store(in: &cancellables)
            
        chatService.iceCandidatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in self?.handleRemoteIceCandidate(data: data) }
            .store(in: &cancellables)
            
        chatService.callEndedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in self?.handleRemoteEnded(data: data) }
            .store(in: &cancellables)
            
        chatService.cameraToggledPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                guard let isOff = data["isOff"] as? Bool else { return }
                self?.isRemoteCameraOff = isOff
            }
            .store(in: &cancellables)
    }
    
    // MARK: - VoIP Push
    
    func handleVoIPPush(payload: [String: Any], completion: @escaping () -> Void) {
        let callerName = payload["callerName"] as? String ?? "Unknown"
        let callerId = payload["callerId"] as? String
        
        print("[CALL] VoIP Push received. Caller: \(callerId ?? "unknown")")
        
        // Critical: force reconnect because socket becomes a zombie in background
        if UIApplication.shared.applicationState != .active {
            print("[CALL] Forcing socket reconnect for VoIP wake...")
            chatService.disconnect()
            chatService.connect()
        } else if !chatService.isConnected {
            print("[CALL] Socket not connected. Reconnecting...")
            chatService.connect()
        }
        
        // Glare/Duplicate push protection
        if callPhase == .incomingRinging && currentOpponentId == callerId {
            print("[CALL] Already ringing for this exact call. Ignoring duplicate push.")
            completion()
            return
        }
        
        // Busy rejection
        if callPhase.isInCall {
            print("[CALL] Already busy in another call. Reporting busyUUID to CallKit.")
            let busyUUID = UUID()
            callKitManager.reportIncomingCall(uuid: busyUUID, callerName: callerName, hasVideo: true) { [weak self] _ in
                self?.callKitManager.endCall(uuid: busyUUID)
                completion()
            }
            return
        }
        
        self.incomingCallData = [
            "callerId": callerId ?? "",
            "callerName": callerName,
            "callerAvatarUrl": payload["callerAvatarUrl"] ?? ""
        ]
        self.currentOpponentId = callerId
        self.hasReceivedRemoteSdp = false
        self.pendingRemoteCandidates.removeAll()
        self.pendingAccept = false
        
        let uuid = UUID()
        self.activeCallUUID = uuid
        
        callKitManager.reportIncomingCall(uuid: uuid, callerName: callerName, hasVideo: true) { [weak self] error in
            print("[CALL] CallKit reported VoIP Push. Error? \(error?.localizedDescription ?? "None")")
            DispatchQueue.main.async {
                self?.transitionTo(.incomingRinging)
                self?.startRingTimeout()
            }
            completion()
        }
    }
    
    // MARK: - Incoming Socket Call (Offer)
    
    private func handleIncomingCall(data: [String: Any]) {
        let callerId = data["callerId"] as? String ?? ""
        let callerName = data["callerName"] as? String ?? "Unknown"
        print("[CALL] Incoming socket offer from \(callerName) (\(callerId))")
        
        // 1. GLARE RESOLUTION
        if callPhase == .outgoingRinging {
            if let myId = myUserId, myId > callerId {
                print("[CALL] Glare: I am caller, ignoring their offer.")
                return
            } else {
                print("[CALL] Glare: They take priority. Switching to receiver.")
                doCleanup(sendEndToRemote: false)
                transitionTo(.idle)
            }
        }
        
        // 2. BUSY CHECK
        if callPhase.isInCall && currentOpponentId != callerId {
            print("[CALL] Busy: Emitting end-call because we are in another call.")
            chatService.emitEndCall(to: callerId)
            return
        }
        
        // 3. RETRY OFFER CHECK (CRITICAL RACE CONDITION FIX)
        // If we are already ringing via VoIP Push for this user, this is just the SDP delivery!
        if (callPhase == .incomingRinging || callPhase == .connecting) && currentOpponentId == callerId {
            print("[CALL] Received SDP offer for active call.")
            self.incomingCallData = data
            if self.pendingAccept, let offerDict = data["offer"] as? [String: Any], let sdp = offerDict["sdp"] as? String {
                print("[CALL] Executing pending accept now that offer has arrived.")
                self.pendingAccept = false
                self.executeWebRTCAccept(opponentId: callerId, sdp: sdp)
            }
            return
        }
        
        // 4. NEW FRESH CALL (App was already open)
        if !callPhase.isInCall {
            incomingCallData = data
            currentOpponentId = callerId
            hasReceivedRemoteSdp = false
            pendingRemoteCandidates.removeAll()
            pendingAccept = false
            
            let uuid = UUID()
            activeCallUUID = uuid
            
            callKitManager.reportIncomingCall(uuid: uuid, callerName: callerName, hasVideo: true) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.transitionTo(.incomingRinging)
                    self?.startRingTimeout()
                }
            }
        }
    }
    
    // MARK: - Outgoing Call
    
    func startCall(to opponentId: String, callerId: String, callerName: String, callerAvatar: String, calleeName: String, calleeAvatar: String) {
        guard callPhase == .idle || !callPhase.isInCall else { return }
        print("[CALL] Starting call to \(opponentId)")
        
        currentOpponentId = opponentId
        myUserId = callerId
        outgoingOpponentName = calleeName
        outgoingOpponentAvatarUrl = calleeAvatar
        
        hasReceivedRemoteSdp = false
        connectionState = .new
        pendingRemoteCandidates.removeAll()
        pendingAccept = false
        
        let uuid = UUID()
        activeCallUUID = uuid
        callKitManager.startOutgoingCall(uuid: uuid, calleeName: calleeName, hasVideo: true)
        
        transitionTo(.outgoingRinging)
        startRingTimeout()
        setupWebRTC()
        
        webRTCClient?.offer { [weak self] sdp in
            let offerDict: [String: Any] = ["type": "offer", "sdp": sdp.sdp]
            let data: [String: Any] = [
                "offer": offerDict, "to": opponentId,
                "callerId": callerId, "callerName": callerName, "callerAvatarUrl": callerAvatar
            ]
            self?.chatService.emitCallUser(data: data)
            self?.startOfferRetry(data: data)
        }
    }
    
    // MARK: - App Lifecycle & AV Route
    
    private func handleAppDidEnterBackground() {
        guard callPhase == .active, let opponentId = currentOpponentId else { return }
        if !isCameraOff {
            localVideoTrack?.isEnabled = false
            chatService.emitCameraToggled(isOff: true, to: opponentId)
        }
    }
    
    private func handleAppWillEnterForeground() {
        guard callPhase == .active, let opponentId = currentOpponentId else { return }
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
    
    // MARK: - WebRTC
    
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
    
    func acceptCall() {
        guard callPhase == .incomingRinging else { return }
        print("[CALL] Accepting call...")
        
        stopTimers()
        transitionTo(.connecting) // Transition immediately to show connecting UI
        
        if let uuid = activeCallUUID {
            callKitManager.answerCall(uuid: uuid)
        }
        
        if let data = incomingCallData,
           let offerDict = data["offer"] as? [String: Any],
           let opponentId = data["callerId"] as? String,
           let sdp = offerDict["sdp"] as? String {
            
            // Fast Path: Socket delivered the offer already
            executeWebRTCAccept(opponentId: opponentId, sdp: sdp)
        } else {
            // Cold Boot / Background Wake Path: Fetch offer via HTTP
            print("[CALL] Socket data missing. Fetching pending offer via HTTP...")
            fetchPendingOfferViaHTTP()
        }
    }
    
    private func fetchPendingOfferViaHTTP() {
        guard let myId = UserDefaults.standard.string(forKey: "userId") else {
            print("[CALL] HTTP Fetch Failed: myUserId not found.")
            return
        }
        
        guard let url = URL(string: "\(APIEndpoints.baseURL)/api/calls/pending/\(myId)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Attach JWT token for backend security
        if let token = UserDefaults.standard.string(forKey: "authToken") {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("[CALL] HTTP Fetch Error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.transitionTo(.failed(reason: "Bağlantı kurulamadı (HTTP Hatası)"))
                }
                return
            }
            
            guard let data = data else { return }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = json["success"] as? Bool, success,
                   let callData = json["data"] as? [String: Any],
                   let offerDict = callData["offer"] as? [String: Any],
                   let opponentId = callData["callerId"] as? String,
                   let sdp = offerDict["sdp"] as? String {
                    
                    print("[CALL] Successfully fetched offer via HTTP!")
                    DispatchQueue.main.async {
                        self.incomingCallData = callData
                        self.currentOpponentId = opponentId
                        self.executeWebRTCAccept(opponentId: opponentId, sdp: sdp)
                    }
                } else {
                    print("[CALL] HTTP returned no pending calls (404) or invalid JSON.")
                    DispatchQueue.main.async {
                        self.transitionTo(.failed(reason: "Arama bulunamadı veya düştü"))
                    }
                }
            } catch {
                print("[CALL] JSON Parse error: \(error.localizedDescription)")
            }
        }
        task.resume()
    }
    
    private func executeWebRTCAccept(opponentId: String, sdp: String) {
        let remoteSdp = RTCSessionDescription(type: .offer, sdp: sdp)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.setupWebRTC()
            
            self.webRTCClient?.set(remoteSdp: remoteSdp) { error in
                DispatchQueue.main.async {
                    if error == nil {
                        self.hasReceivedRemoteSdp = true
                        self.processPendingCandidates()
                    }
                }
                
                self.webRTCClient?.answer { answerSdp in
                    let answerDict: [String: Any] = ["type": "answer", "sdp": answerSdp.sdp]
                    let emitData: [String: Any] = ["answer": answerDict, "to": opponentId]
                    self.chatService.emitAnswerCall(data: emitData)
                }
            }
        }
    }
    
    private func handleCallAnswered(data: [String: Any]) {
        guard callPhase == .outgoingRinging else { return }
        print("[CALL] Remote answered.")
        
        stopTimers()
        transitionTo(.connecting)
        
        if let uuid = activeCallUUID {
            callKitManager.reportCallConnected(uuid: uuid)
        }
        
        guard let answerDict = data["answer"] as? [String: Any],
              let sdp = answerDict["sdp"] as? String else { return }
        
        let remoteSdp = RTCSessionDescription(type: .answer, sdp: sdp)
        webRTCClient?.set(remoteSdp: remoteSdp) { [weak self] error in
            DispatchQueue.main.async {
                if error == nil {
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
            pendingRemoteCandidates.append(candidate)
        }
    }
    
    private func processPendingCandidates() {
        for c in pendingRemoteCandidates {
            webRTCClient?.set(remoteCandidate: c)
        }
        pendingRemoteCandidates.removeAll()
    }
    
    // MARK: - End Call
    
    func dismissCall() {
        if callPhase.isInCall {
            print("[CALL] Ignored spurious dismissCall() while active.")
            return
        }
        transitionTo(.idle)
    }
    
    func endCall() {
        if case .failed = callPhase { return }
        if !callPhase.isInCall { return }
        print("[CALL] User explicitly ended the call.")
        doCleanup(sendEndToRemote: true)
    }
    
    private func handleRemoteEnded(data: [String: Any]) {
        print("[CALL] Remote ended the call payload: \(data)")
        
        if callPhase == .outgoingRinging {
            transitionTo(.failed(reason: "Unavailable"))
            doCleanup(sendEndToRemote: false)
        } else if callPhase.isInCall {
            transitionTo(.ended)
            doCleanup(sendEndToRemote: false)
        }
    }
    
    private func doCleanup(sendEndToRemote: Bool) {
        if sendEndToRemote, let opponentId = currentOpponentId {
            chatService.emitEndCall(to: opponentId)
        }
        
        if let uuid = activeCallUUID {
            callKitManager.endCall(uuid: uuid)
            activeCallUUID = nil
        }
        
        webRTCClient?.close()
        webRTCClient = nil
        
        if callPhase == .active || callPhase == .connecting {
            transitionTo(.ended)
        } else if callPhase == .incomingRinging {
            transitionTo(.idle)
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.incomingCallData = nil
            self.currentOpponentId = nil
            self.outgoingOpponentName = nil
            self.outgoingOpponentAvatarUrl = nil
            self.remoteVideoTrack = nil
            self.localVideoTrack = nil
            self.connectionState = .new
        }
    }
    
    func toggleMute() {
        isMuted.toggle()
        webRTCClient?.setAudioEnabled(!isMuted)
    }
    
    func toggleCamera() {
        isCameraOff.toggle()
        localVideoTrack?.isEnabled = !isCameraOff
        if let toId = currentOpponentId {
            chatService.emitCameraToggled(isOff: isCameraOff, to: toId)
        }
    }
    
    func switchCamera() { webRTCClient?.switchCamera() }
    func toggleSpeaker() {
        isSpeakerOn.toggle()
        webRTCClient?.setAudioRoute(toSpeaker: isSpeakerOn)
    }
}

extension CallManager: WebRTCClientDelegate {
    func webRTCClient(_ client: WebRTCClient, didDiscoverLocalCandidate candidate: RTCIceCandidate) {
        guard let toId = currentOpponentId else { return }
        let candidateDict: [String: Any] = ["candidate": candidate.sdp, "sdpMid": candidate.sdpMid ?? "", "sdpMLineIndex": candidate.sdpMLineIndex]
        chatService.emitIceCandidate(data: ["candidate": candidateDict, "to": toId])
    }
    
    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCIceConnectionState) {
        DispatchQueue.main.async { [weak self] in
            self?.connectionState = state
            if state == .connected {
                self?.transitionTo(.active)
                self?.iceRecoveryTimer?.invalidate()
            } else if state == .disconnected || state == .failed {
                print("[CALL] ICE disconnected/failed.")
                self?.iceRecoveryTimer?.invalidate()
                self?.iceRecoveryTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                    if self?.callPhase == .active || self?.callPhase == .connecting {
                        self?.transitionTo(.failed(reason: "Connection lost"))
                        self?.doCleanup(sendEndToRemote: true)
                    }
                }
            }
        }
    }
    
    func webRTCClient(_ client: WebRTCClient, didReceiveData data: Data) {}
    func webRTCClient(_ client: WebRTCClient, didReceiveRemoteVideoTrack track: RTCVideoTrack) {
        DispatchQueue.main.async { [weak self] in self?.remoteVideoTrack = track }
    }
}

extension CallManager: CallKitManagerDelegate {
    func callKitDidAnswerCall(uuid: UUID) {
        DispatchQueue.main.async { [weak self] in self?.acceptCall() }
    }
    
    func callKitDidEndCall(uuid: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("[CALL] CallKit delegate hit for UUID: \(uuid). Active is: \(self.activeCallUUID?.uuidString ?? "nil")")
            if let active = self.activeCallUUID, active != uuid {
                print("[CALL] Ignoring CallKit end for non-active UUID (likely busy rejection).")
                return
            }
            self.activeCallUUID = nil
            if self.callPhase.isInCall { self.endCall() }
        }
    }
}
