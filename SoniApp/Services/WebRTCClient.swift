import Foundation
import WebRTC

protocol WebRTCClientDelegate: AnyObject {
    func webRTCClient(_ client: WebRTCClient, didDiscoverLocalCandidate candidate: RTCIceCandidate)
    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCIceConnectionState)
    func webRTCClient(_ client: WebRTCClient, didReceiveData data: Data)
    func webRTCClient(_ client: WebRTCClient, didReceiveRemoteVideoTrack track: RTCVideoTrack)
}

final class WebRTCClient: NSObject {
    
    // MARK: - Properties
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
    }()
    
    private let peerConnection: RTCPeerConnection
    private let rtcAudioSession =  RTCAudioSession.sharedInstance()
    private let audioQueue = DispatchQueue(label: "audio")
    private let mediaConstrains = [kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                                   kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue]
    
    weak var delegate: WebRTCClientDelegate?
    var localVideoTrack: RTCVideoTrack?
    var remoteVideoTrack: RTCVideoTrack?
    var localAudioTrack: RTCAudioTrack?
    

    
    var videoCapturer: RTCVideoCapturer?
    private var isFrontCamera = true
    
    // STUN Servers (Google)
    private let rtcConfig: RTCConfiguration = {
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        return config
    }()
    
    private let mediaConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])
    
    override init() {
        // Create Peer Connection
        self.peerConnection = WebRTCClient.factory.peerConnection(with: rtcConfig, constraints: mediaConstraints, delegate: nil)!
        
        super.init()
        self.setupAudioSession()
        self.peerConnection.delegate = self
        self.setupLocalTracks()
    }
    
    // MARK: - Setup
    private func setupAudioSession() {
        #if targetEnvironment(simulator)
        rtcAudioSession.useManualAudio = false
        rtcAudioSession.isAudioEnabled = true
        #else
        rtcAudioSession.useManualAudio = true
        rtcAudioSession.isAudioEnabled = false
        #endif
        
        rtcAudioSession.lockForConfiguration()
        do {
            let configuration = RTCAudioSessionConfiguration.webRTC()
            configuration.category = AVAudioSession.Category.playAndRecord.rawValue
            configuration.mode = AVAudioSession.Mode.voiceChat.rawValue
            configuration.categoryOptions = [.allowBluetoothHFP, .allowBluetoothA2DP]
            
            #if targetEnvironment(simulator)
            try rtcAudioSession.setConfiguration(configuration, active: true)
            print("[WebRTCClient] Audio session configured for Simulator (CallKit bypassed).")
            #else
            try rtcAudioSession.setConfiguration(configuration, active: false)
            print("[WebRTCClient] Audio session configured for manual CallKit use.")
            #endif
        } catch {
            print("[WebRTCClient] Error configuring audio session: \(error)")
        }
        rtcAudioSession.unlockForConfiguration()
    }
    
    private func setupLocalTracks() {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let source = WebRTCClient.factory.audioSource(with: constraints)
        let track = WebRTCClient.factory.audioTrack(with: source, trackId: "audio0")
        self.localAudioTrack = track
        self.peerConnection.add(track, streamIds: ["stream0"])
        
        // Video
        let videoSource = WebRTCClient.factory.videoSource()
        
        #if targetEnvironment(simulator)
            print("Simulator environment: Camera disabled, sending empty video track.")
        #else
            let capturer = RTCCameraVideoCapturer(delegate: videoSource)
            self.videoCapturer = capturer
            let devices = RTCCameraVideoCapturer.captureDevices()
            if let frontCamera = devices.first(where: { $0.position == .front }) {
                if let format = RTCCameraVideoCapturer.supportedFormats(for: frontCamera).first {
                    let fps = format.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 30
                    capturer.startCapture(with: frontCamera, format: format, fps: Int(fps))
                }
            }
        #endif
        
        let videoTrack = WebRTCClient.factory.videoTrack(with: videoSource, trackId: "video0")
        self.localVideoTrack = videoTrack
        self.peerConnection.add(videoTrack, streamIds: ["stream0"])
    }
    
    // MARK: - Camera Controls
    func switchCamera() {
        #if !targetEnvironment(simulator)
        guard let capturer = self.videoCapturer as? RTCCameraVideoCapturer else { return }
        
        isFrontCamera.toggle()
        let position: AVCaptureDevice.Position = isFrontCamera ? .front : .back
        
        let devices = RTCCameraVideoCapturer.captureDevices()
        if let camera = devices.first(where: { $0.position == position }),
           let format = RTCCameraVideoCapturer.supportedFormats(for: camera).first {
            let fps = format.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 30
            
            // Must stop current camera before starting another — AVCaptureSession will crash otherwise
            capturer.stopCapture {
                capturer.startCapture(with: camera, format: format, fps: Int(fps))
                print("[WebRTCClient] Switched camera to \(position == .front ? "Front" : "Back").")
            }
        }
        #endif
    }
    
    // MARK: - Audio Controls
    func setAudioEnabled(_ isEnabled: Bool) {
        localAudioTrack?.isEnabled = isEnabled
    }
    
    func setAudioRoute(toSpeaker: Bool) {
        rtcAudioSession.lockForConfiguration()
        do {
            try rtcAudioSession.overrideOutputAudioPort(toSpeaker ? .speaker : .none)
            print("[WebRTCClient] Audio route explicitly set to \(toSpeaker ? "Speaker" : "Earpiece").")
        } catch {
            print("[WebRTCClient] Error setting audio route to speaker=\(toSpeaker): \(error)")
        }
        rtcAudioSession.unlockForConfiguration()
    }
    
    // MARK: - Signaling
    func offer(completion: @escaping (_ sdp: RTCSessionDescription) -> Void) {
        let constrains = RTCMediaConstraints(mandatoryConstraints: self.mediaConstrains, optionalConstraints: nil)
        self.peerConnection.offer(for: constrains) { (sdp, error) in
            guard let sdp = sdp else { return }
            self.peerConnection.setLocalDescription(sdp, completionHandler: { (error) in
                completion(sdp)
            })
        }
    }
    
    func answer(completion: @escaping (_ sdp: RTCSessionDescription) -> Void) {
        let constrains = RTCMediaConstraints(mandatoryConstraints: self.mediaConstrains, optionalConstraints: nil)
        self.peerConnection.answer(for: constrains) { (sdp, error) in
            guard let sdp = sdp else { return }
            self.peerConnection.setLocalDescription(sdp, completionHandler: { (error) in
                completion(sdp)
            })
        }
    }
    
    func set(remoteSdp: RTCSessionDescription, completion: @escaping (Error?) -> Void) {
        self.peerConnection.setRemoteDescription(remoteSdp, completionHandler: completion)
    }
    
    func set(remoteCandidate: RTCIceCandidate) {
        self.peerConnection.add(remoteCandidate) { error in
            if let error = error {
                print("Error adding remote ICE candidate: \(error)")
            }
        }
    }
    
    // MARK: - Teardown
    func close() {
        print("[WebRTCClient] Closing connection and stopping media capture.")
        
        rtcAudioSession.lockForConfiguration()
        do {
            try rtcAudioSession.setActive(false)
        } catch {
            print("[WebRTCClient] Error deactivating audio session: \(error)")
        }
        rtcAudioSession.unlockForConfiguration()
        
        // Stop Camera
        if let capturer = videoCapturer as? RTCCameraVideoCapturer {
            capturer.stopCapture()
        }
        
        // Remove tracks
        for sender in peerConnection.senders {
            peerConnection.removeTrack(sender)
        }
        
        // Dettach remote view if necessary, stop peer connection
        peerConnection.close()
        peerConnection.delegate = nil
        self.delegate = nil
    }
}

// MARK: - PeerConnectionDelegate
extension WebRTCClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("WebRTC Signaling State: \(stateChanged.rawValue)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("WebRTC Connection State: \(newState.rawValue)")
        self.delegate?.webRTCClient(self, didChangeConnectionState: newState)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("WebRTC Stream Added: \(stream.streamId)")
        if let track = stream.videoTracks.first {
            print("WebRTC Video Track Found in stream")
            self.remoteVideoTrack = track
            self.delegate?.webRTCClient(self, didReceiveRemoteVideoTrack: track)
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        self.delegate?.webRTCClient(self, didDiscoverLocalCandidate: candidate)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
