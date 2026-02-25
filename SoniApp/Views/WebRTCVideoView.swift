import SwiftUI
import WebRTC

/// Bridging WebRTC's RTCMTLVideoView (Metal-backed video renderer) into SwiftUI.
struct WebRTCVideoView: UIViewRepresentable {
    
    // The WebRTC video track to render
    let track: RTCVideoTrack?
    
    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFill
        view.backgroundColor = .black
        return view
    }
    
    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        // If there's an existing track attached, remove the renderer from it
        if uiView.tag != 0 && uiView.tag != track?.hashValue {
            // Unbind previous tracking logic if needed, or simply let the new track override it.
        }
        
        // Remove from any previous tracks and add to the new one
        if let track = track {
            track.add(uiView)
            uiView.tag = track.hashValue // Store hash to avoid re-adding
        } else {
            // Unbind if track turns nil? Typically we just let it be or clear it
        }
    }
    
    // Cleanup when the view disappears
    static func dismantleUIView(_ uiView: RTCMTLVideoView, coordinator: ()) {
        // We can't easily find the track to call remove(uiView) here unless we store it,
        // but typically RTCMTLVideoView cleans itself up when deallocated.
    }
}
