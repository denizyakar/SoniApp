import Foundation
import SwiftUI
import Combine
import WebRTC

struct CallView: View {
    let opponentId: String
    let opponentName: String
    let opponentAvatarUrl: String
    
    @EnvironmentObject var callManager: CallManager
    
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
            
            switch callManager.callPhase {
            case .incomingRinging:
                incomingCallView
            case .outgoingRinging:
                outgoingCallView
            case .connecting:
                connectingView
            case .active:
                activeCallView
            case .failed(let reason):
                failedCallView(reason: reason)
            case .ended:
                endedView
            case .idle:
                EmptyView()
            }
        }
        .onReceive(timer) { _ in
            if callManager.callPhase == .active {
                // Mock audio wave for visual testing
                withAnimation(.linear(duration: 0.2)) {
                    audioLevel = CGFloat.random(in: 0.1...1.0)
                }
            }
        }
    }
    
    // MARK: - Incoming Call View
    
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
                Button(action: { endCall() }) {
                    ZStack {
                        Circle().fill(Color.red).frame(width: 80, height: 80)
                        Image(systemName: "phone.down.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                }
                
                Button(action: { acceptCall() }) {
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
    
    // MARK: - Outgoing Call View
    
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
            
            Button(action: { endCall() }) {
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
    
    // MARK: - Connecting View
    
    private var connectingView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            AvatarView(imageUrl: URL(string: opponentAvatarUrl), size: 100)
                .clipShape(Circle())
            
            Text(opponentName)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            
            Text("Connecting...")
                .font(.title3)
                .foregroundColor(.white.opacity(0.7))
            
            Spacer()
            
            Button(action: { endCall() }) {
                ZStack {
                    Circle().fill(Color.red).frame(width: 70, height: 70)
                    Image(systemName: "phone.down.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
            .padding(.bottom, 60)
        }
    }
    
    // MARK: - Active Call View
    
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
                            // Snapping logic
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
    
    // MARK: - Failed Call View
    
    private func failedCallView(reason: String) -> some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)
            
            Text("Call Failed")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text(reason)
                .font(.title3)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
            
            Button(action: { callManager.dismissCall() }) {
                Text("Close")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 200, height: 50)
                    .background(AppTheme.primary)
                    .cornerRadius(25)
            }
            .padding(.bottom, 60)
        }
    }
    
    // MARK: - Ended View
    
    private var endedView: some View {
        VStack {
            Spacer()
            Text("Call Ended")
                .font(.title2.weight(.medium))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
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
                    .scaleEffect(x: -1, y: 1) // Mirror effect
            } else {
                Color.gray.opacity(0.3)
                #if targetEnvironment(simulator)
                VStack {
                    Image(systemName: "desktopcomputer")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                    Text("Simulator (No Camera)")
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
                    
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.3)
                        .padding(.vertical, 12)
                    
                    Text("Waiting for video...")
                        .font(.body.weight(.medium))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
        }
    }
    
    private var controlsArea: some View {
        HStack(spacing: 20) {
            // Camera Button
            Button(action: { callManager.toggleCamera() }) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.2)).frame(width: 55, height: 55)
                    Image(systemName: callManager.isCameraOff ? "video.slash.fill" : "video.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                }
            }
            
            // Flip Camera Button (Front/Back)
            Button(action: { callManager.switchCamera() }) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.2)).frame(width: 55, height: 55)
                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                }
            }
            
            // Mic Button
            Button(action: { callManager.toggleMute() }) {
                ZStack {
                    Circle().fill(callManager.isMuted ? Color.white.opacity(0.9) : Color.white.opacity(0.2)).frame(width: 55, height: 55)
                    Image(systemName: callManager.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.title3)
                        .foregroundColor(callManager.isMuted ? .black : .white)
                }
            }
            
            // Speaker Button
            Button(action: { callManager.toggleSpeaker() }) {
                ZStack {
                    Circle().fill(callManager.isSpeakerOn ? Color.white.opacity(0.2) : Color.white.opacity(0.9)).frame(width: 55, height: 55)
                    Image(systemName: callManager.isSpeakerOn ? "speaker.wave.3.fill" : "iphone")
                        .font(.title3)
                        .foregroundColor(callManager.isSpeakerOn ? .white : .black)
                }
            }
            
            // End Call Button
            Button(action: { endCall() }) {
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
    }
}

#Preview("Outgoing Call") {
    let container = DependencyContainer()
    CallView(opponentId: "123", opponentName: "Ali Veli", opponentAvatarUrl: "")
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
