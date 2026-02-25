import Foundation
import SwiftUI
import Combine
import WebRTC

/// Call screen states
enum CallState {
    case incoming // Opponent is calling, accept/decline screen
    case outgoing // We are calling, waiting for opponent to answer
    case active   // Call in progress
    case ended    // Call ended (dismiss screen)
}

struct CallView: View {
    let opponentId: String
    let opponentName: String
    let opponentAvatarUrl: String
    
    @Binding var isPresented: Bool
    
    @EnvironmentObject var callManager: CallManager
    
    // UI State Computed from CallManager
    private var callState: CallState {
        if callManager.connectionState == .connected || callManager.connectionState == .completed {
            return .active
        } else if callManager.hasAnsweredCall {
            // Answered but not fully connected yet — still show Active (Video) screen
            return .active
        } else if callManager.incomingCallData != nil {
            return .incoming
        } else {
            return .outgoing
        }
    }
    
    // PIP (Picture-in-Picture) Draggable State
    @State private var pipPosition: CGPoint = CGPoint(x: UIScreen.main.bounds.width - 80, y: 150)
    @State private var isPIPSwapped: Bool = false // If true, opponent is in PIP, we are fullscreen
    
    // Audio wave animation (mock)
    @State private var audioLevel: CGFloat = 0.2
    let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // Background
            AppTheme.backgroundLight.ignoresSafeArea()
            
            if callState == .incoming {
                incomingCallView
            } else if callState == .outgoing {
                outgoingCallView
            } else if callState == .active {
                activeCallView
            }
        }
        .onReceive(timer) { _ in
            if callState == .active {
                // Mock audio wave for visual testing
                withAnimation(.linear(duration: 0.2)) {
                    audioLevel = CGFloat.random(in: 0.1...1.0)
                }
            }
        }
    }
    
    // MARK: - Views
    
    private var incomingCallView: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Profile Photo and Name
            VStack(spacing: 16) {
                AvatarView(imageUrl: URL(string: opponentAvatarUrl), size: 120)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 2))
                    .shadow(radius: 10)
                
                Text(opponentName)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("Video Calling...")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            // Accept/Decline Buttons
            HStack(spacing: 60) {
                Button(action: {
                    endCall()
                }) {
                    ZStack {
                        Circle().fill(Color.red).frame(width: 80, height: 80)
                        Image(systemName: "phone.down.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                }
                
                Button(action: {
                    acceptCall()
                }) {
                    ZStack {
                        Circle().fill(Color.green).frame(width: 80, height: 80)
                        Image(systemName: "phone.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.bottom, 60)
        }
    }
    
    private var outgoingCallView: some View {
        VStack(spacing: 40) {
            Spacer()
            
            AvatarView(imageUrl: URL(string: opponentAvatarUrl), size: 120)
                .clipShape(Circle())
                .opacity(0.8)
            
            Text(opponentName)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text("Ringing...")
                .font(.title3)
                .foregroundColor(AppTheme.secondaryText)
                .bold()
            
            Spacer()
            
            Button(action: {
                endCall()
            }) {
                ZStack {
                    Circle().fill(Color.red).frame(width: 80, height: 80)
                    Image(systemName: "phone.down.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }
            }
            .padding(.bottom, 60)
        }
    }
    
    private var activeCallView: some View {
        ZStack {
            // Main Fullscreen Video
            mainVideoArea
                .ignoresSafeArea()
            
            // Floating Top Overlay (Name and Audio Wave)
            VStack {
                HStack {
                    ZStack {
                        Capsule()
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 150, height: 40)
                        
                        HStack(spacing: 8) {
                            Text(opponentName)
                                .font(.subheadline).bold()
                                .foregroundColor(.white)
                            
                            // Audio Indicator (Mock)
                            HStack(spacing: 2) {
                                ForEach(0..<3) { i in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.green)
                                        .frame(width: 3, height: audioLevel * CGFloat(15 - (i * 3)))
                                }
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.top, 50)
                .padding(.horizontal)
                Spacer()
            }
            
            // PIP Video (Draggable & Swappable)
            pipVideoArea
                .position(pipPosition)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            pipPosition = value.location
                        }
                        .onEnded { value in
                            // Snapping logic can be added here
                            let screenW = UIScreen.main.bounds.width
                            let screenH = UIScreen.main.bounds.height
                            let padding: CGFloat = 80
                            
                            let targetX = value.location.x < screenW / 2 ? padding : screenW - padding
                            let targetY = max(padding + 50, min(value.location.y, screenH - padding - 100))
                            
                            withAnimation(.spring()) {
                                pipPosition = CGPoint(x: targetX, y: targetY)
                            }
                        }
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isPIPSwapped.toggle()
                    }
                }
            
            // Bottom Controls
            VStack {
                Spacer()
                controlsArea
            }
        }
    }
    
    // MARK: - Subcomponents
    
    @ViewBuilder
    private var mainVideoArea: some View {
        if isPIPSwapped {
            // We are fullscreen
            localVideoMock
        } else {
            // Opponent is fullscreen
            remoteVideoMock
        }
    }
    
    @ViewBuilder
    private var pipVideoArea: some View {
        ZStack {
            if isPIPSwapped {
                // Opponent is in PIP
                remoteVideoMock
            } else {
                // We are in PIP
                localVideoMock
            }
        }
        .frame(width: 120, height: 160)
        .cornerRadius(12)
        .shadow(radius: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        )
    }
    
    private var localVideoMock: some View {
        ZStack {
            if let track = callManager.localVideoTrack {
                WebRTCVideoView(track: track)
                    .scaleEffect(x: -1, y: 1) // Ayna efekti
            } else {
                Color.gray.opacity(0.3)
                #if targetEnvironment(simulator)
                VStack {
                    Image(systemName: "desktopcomputer")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                    Text("Simulator (Kamera Yok)")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                #else
                Image(systemName: "camera.fill")
                    .foregroundColor(.white)
                #endif
            }
            
            if callManager.isCameraOff {
                Color.black
                Image(systemName: "video.slash.fill")
                    .foregroundColor(.white)
            }
        }
    }
    
    private var isConnectionFailed: Bool {
        let state = callManager.connectionState
        return state == .failed || state == .disconnected || state == .closed
    }
    
    private var connectingStatusText: String {
        let state = callManager.connectionState
        if isConnectionFailed {
            return "Connection failed. Please try again."
        } else if state == .checking {
            return "Connection quality is being verified..."
        } else {
            if callManager.incomingCallData != nil {
                return "Connecting..."
            } else {
                return "Call accepted, connecting..."
            }
        }
    }
    
    private var remoteVideoMock: some View {
        ZStack {
            if let track = callManager.remoteVideoTrack, !callManager.isRemoteCameraOff {
                WebRTCVideoView(track: track)
            } else if callManager.isRemoteCameraOff {
                Color.gray.opacity(0.8)
                VStack {
                    Image(systemName: "video.slash.fill")
                        .foregroundColor(.white)
                        .font(.largeTitle)
                        .padding(.bottom, 8)
                    Text("\(opponentName) paused their camera")
                        .font(.body.weight(.medium))
                        .foregroundColor(.white)
                }
            } else {
                AppTheme.primaryLight
                VStack {
                    AvatarView(imageUrl: URL(string: opponentAvatarUrl), size: 60)
                    
                    if !isConnectionFailed {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.3)
                            .padding(.vertical, 12)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.title)
                            .padding(.vertical, 12)
                    }
                    
                    Text(connectingStatusText)
                        .font(.body.weight(.medium))
                        .foregroundColor(isConnectionFailed ? .red : .white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
        }
    }
    
    private var controlsArea: some View {
        HStack(spacing: 20) {
            // Kamera Butonu
            Button(action: {
                callManager.toggleCamera()
            }) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.2)).frame(width: 55, height: 55)
                    Image(systemName: callManager.isCameraOff ? "video.slash.fill" : "video.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                }
            }
            
            // Flip Camera Button (Front/Back)
            Button(action: {
                callManager.switchCamera()
            }) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.2)).frame(width: 55, height: 55)
                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                }
            }
            
            // Mikrofon Butonu
            Button(action: {
                callManager.toggleMute()
            }) {
                ZStack {
                    Circle().fill(callManager.isMuted ? Color.white.opacity(0.9) : Color.white.opacity(0.2)).frame(width: 55, height: 55)
                    Image(systemName: callManager.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.title3)
                        .foregroundColor(callManager.isMuted ? .black : .white)
                }
            }
            
            // Speaker Button
            Button(action: {
                callManager.toggleSpeaker()
            }) {
                ZStack {
                    Circle().fill(callManager.isSpeakerOn ? Color.white.opacity(0.2) : Color.white.opacity(0.9)).frame(width: 55, height: 55)
                    Image(systemName: callManager.isSpeakerOn ? "speaker.wave.3.fill" : "iphone")
                        .font(.title3)
                        .foregroundColor(callManager.isSpeakerOn ? .white : .black)
                }
            }
            
            // Kapatma Butonu
            Button(action: {
                endCall()
            }) {
                ZStack {
                    Circle().fill(Color.red).frame(width: 55, height: 55)
                    Image(systemName: "phone.down.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.bottom, 40)
        .padding(.top, 20)
        .background(
            LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0.8), Color.clear]), startPoint: .bottom, endPoint: .top)
        )
    }
    
    // MARK: - Actions
    
    private func acceptCall() {
        callManager.acceptCall()
    }
    
    private func endCall() {
        callManager.endCall()
        isPresented = false
    }
}

#Preview("Outgoing Call") {
    let container = DependencyContainer()
    CallView(opponentId: "123", opponentName: "Ali Veli", opponentAvatarUrl: "", isPresented: .constant(true))
        .environmentObject(container.callManager)
}

#Preview("Incoming Call Mock") {
    ZStack {
        AppTheme.primary.ignoresSafeArea()
        
        VStack(spacing: 40) {
            Spacer()
            
            VStack(spacing: 16) {
                AvatarView(sfSymbol: "person.circle", size: 120)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 2))
                    .shadow(radius: 10)
                
                Text("Ali Veli")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("Video Calling...")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
                    .bold()
            }
            
            Spacer()
            
            HStack(spacing: 60) {
                ZStack {
                    Circle().fill(Color.red).frame(width: 80, height: 80)
                    Image(systemName: "phone.down.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }
                
                ZStack {
                    Circle().fill(Color.green).frame(width: 80, height: 80)
                    Image(systemName: "phone.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }
            }
            .padding(.bottom, 60)
        }
    }
}
