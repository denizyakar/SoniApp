//
//  ChatServiceProtocol.swift
//  SoniApp
//

import Foundation
import SocketIO
import Combine

// MARK: - Protocol

protocol ChatServiceProtocol {
    var messagePublisher: AnyPublisher<Message, Never> { get }
    var userRegisteredPublisher: AnyPublisher<Void, Never> { get }
    var messageReadPublisher: AnyPublisher<[String], Never> { get }
    var connectionStatePublisher: AnyPublisher<Bool, Never> { get }
    var profileUpdatedPublisher: AnyPublisher<(String, String, String, String), Never> { get }
    var isConnected: Bool { get }
    
    func connect()
    func disconnect()
    func sendMessage(text: String, senderId: String, receiverId: String, clientId: String?, imageUrl: String?)
    func uploadMessageImage(_ data: Data) async throws -> String
    func sendReadReceipt(messageIds: [String], readerId: String)
    
    var cameraToggledPublisher: AnyPublisher<[String: Any], Never> { get }
    func emitCameraToggled(isOff: Bool, to opponentId: String)
}

// MARK: - Implementation

final class SocketChatService: ChatServiceProtocol {
    
    // MARK: - Subjects
    private let _messageSubject = PassthroughSubject<Message, Never>()
    private let _userRegisteredSubject = PassthroughSubject<Void, Never>()
    private let _messageReadSubject = PassthroughSubject<[String], Never>()
    private let _connectionStateSubject = PassthroughSubject<Bool, Never>()
    private let _profileUpdatedSubject = PassthroughSubject<(String, String, String, String), Never>()
    private let _incomingCallSubject = PassthroughSubject<[String: Any], Never>()
    private let _callAnsweredSubject = PassthroughSubject<[String: Any], Never>()
    private let _iceCandidateSubject = PassthroughSubject<[String: Any], Never>()
    private let _callEndedSubject = PassthroughSubject<[String: Any], Never>()
    private let _cameraToggledSubject = PassthroughSubject<[String: Any], Never>()
    
    // MARK: - Publishers
    
    var messagePublisher: AnyPublisher<Message, Never> {
        _messageSubject.eraseToAnyPublisher()
    }
    
    var userRegisteredPublisher: AnyPublisher<Void, Never> {
        _userRegisteredSubject.eraseToAnyPublisher()
    }
    
    var messageReadPublisher: AnyPublisher<[String], Never> {
        _messageReadSubject.eraseToAnyPublisher()
    }
    
    var connectionStatePublisher: AnyPublisher<Bool, Never> {
        _connectionStateSubject.eraseToAnyPublisher()
    }
    
    var profileUpdatedPublisher: AnyPublisher<(String, String, String, String), Never> {
        _profileUpdatedSubject.eraseToAnyPublisher()
    }
    
    // MARK: - WebRTC Publishers
    var incomingCallPublisher: AnyPublisher<[String: Any], Never> {
        _incomingCallSubject.eraseToAnyPublisher()
    }
    var callAnsweredPublisher: AnyPublisher<[String: Any], Never> {
        _callAnsweredSubject.eraseToAnyPublisher()
    }
    var iceCandidatePublisher: AnyPublisher<[String: Any], Never> {
        _iceCandidateSubject.eraseToAnyPublisher()
    }
    var callEndedPublisher: AnyPublisher<[String: Any], Never> {
        _callEndedSubject.eraseToAnyPublisher()
    }
    var cameraToggledPublisher: AnyPublisher<[String: Any], Never> {
        _cameraToggledSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Socket.IO
    private var manager: SocketManager
    private var socket: SocketIOClient
    private(set) var isConnected: Bool = false
    
    // MARK: - Init
    init() {
        let url = URL(string: APIEndpoints.baseURL)!
        
        manager = SocketManager(socketURL: url, config: [
            .log(false),
            .compress,
            .forceWebsockets(true)
        ])
        socket = manager.defaultSocket
        
        setupListeners()
    }
    
    private var currentUserIdForSocket: String?
    
    // MARK: - Connection
    
    func connect() {
        guard !isConnected else { return }
        
        if let currentUserId = UserDefaults.standard.string(forKey: "userId") {
            self.currentUserIdForSocket = currentUserId
        }
        
        print("[SocketService] Connecting...")
        socket.connect()
    }
    
    func disconnect() {
        socket.disconnect()
        isConnected = false
    }
    
    func sendMessage(text: String, senderId: String, receiverId: String, clientId: String? = nil, imageUrl: String? = nil) {
        var data: [String: Any] = [
            "text": text,
            "senderId": senderId,
            "receiverId": receiverId
        ]
        if let clientId = clientId {
            data["clientId"] = clientId
        }
        if let imageUrl = imageUrl {
            data["imageUrl"] = imageUrl
        }
        socket.emit("chat_message", data)
    }
    
    // MARK: - Image Upload
    func uploadMessageImage(_ data: Data) async throws -> String {
        let url = URL(string: "\(APIEndpoints.baseURL)/messages/upload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"message_image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ImageUploadError(message: "Upload failed")
        }
        
        struct UploadResponse: Decodable {
            let imageUrl: String
        }
        
        let result = try JSONDecoder().decode(UploadResponse.self, from: responseData)
        return result.imageUrl
    }
    
    struct ImageUploadError: Error { let message: String }
    
    // MARK: - Read Receipts
    func sendReadReceipt(messageIds: [String], readerId: String) {
        guard !messageIds.isEmpty else { return }
        let data: [String: Any] = [
            "messageIds": messageIds,
            "readerId": readerId
        ]
        socket.emit("mark_as_read", data)
    }
    
    // MARK: - Profile Broadcast
    func emitProfileUpdate(userId: String, nickname: String, avatarName: String, avatarUrl: String) {
        let data: [String: Any] = [
            "userId": userId,
            "nickname": nickname,
            "avatarName": avatarName,
            "avatarUrl": avatarUrl
        ]
        socket.emit("profile_updated", data)
    }
    
    // MARK: - WebRTC Emitters
    
    func emitCallUser(data: [String: Any]) {
        socket.emit("call-user", data)
    }
    
    func emitAnswerCall(data: [String: Any]) {
        socket.emit("answer-call", data)
    }
    
    func emitIceCandidate(data: [String: Any]) {
        socket.emit("ice-candidate", data)
    }
    
    func emitEndCall(to opponentId: String) {
        let data: [String: Any] = ["to": opponentId]
        socket.emit("end-call", data)
    }
    
    func emitCameraToggled(isOff: Bool, to opponentId: String) {
        let data: [String: Any] = ["to": opponentId, "isOff": isOff]
        socket.emit("camera-toggled", data)
    }
    
    // MARK: - Socket Listeners
    private func setupListeners() {
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            print("[SocketService] Connected ✅")
            self?.isConnected = true
            if let uid = self?.currentUserIdForSocket {
                self?.socket.emit("register", uid)
            }
            self?._connectionStateSubject.send(true)
        }
        
        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            print("[SocketService] Disconnected ⚠️")
            self?.isConnected = false
            self?._connectionStateSubject.send(false)
        }
        
        socket.on("user_registered") { [weak self] _, _ in
            self?._userRegisteredSubject.send()
        }
        
        socket.on("receive_message") { [weak self] data, _ in
            guard let dataArray = data as? [[String: Any]],
                  let json = dataArray.first else { return }
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: json)
                let message = try JSONDecoder().decode(Message.self, from: jsonData)
                self?._messageSubject.send(message)
            } catch {
                print("[SocketService] Message parse error: \(error)")
            }
        }
        
        socket.on("read_receipt") { [weak self] data, _ in
            guard let dataArray = data as? [[String: Any]],
                  let json = dataArray.first,
                  let messageIds = json["messageIds"] as? [String] else { return }
            
            self?._messageReadSubject.send(messageIds)
        }
        
        socket.on("profile_updated") { [weak self] data, _ in
            guard let dataArray = data as? [[String: Any]],
                  let json = dataArray.first,
                  let userId = json["userId"] as? String,
                  let nickname = json["nickname"] as? String,
                  let avatarName = json["avatarName"] as? String else { return }
            
            let avatarUrl = json["avatarUrl"] as? String ?? ""
            
            self?._profileUpdatedSubject.send((userId, nickname, avatarName, avatarUrl))
        }
        
        // MARK: WebRTC Listeners
        
        socket.on("call-made") { [weak self] data, _ in
            guard let dataArray = data as? [[String: Any]],
                  let json = dataArray.first else { return }
            self?._incomingCallSubject.send(json)
        }
        
        socket.on("call-answered") { [weak self] data, _ in
            guard let dataArray = data as? [[String: Any]],
                  let json = dataArray.first else { return }
            self?._callAnsweredSubject.send(json)
        }
        
        socket.on("ice-candidate") { [weak self] data, _ in
            guard let dataArray = data as? [[String: Any]],
                  let json = dataArray.first else { return }
            self?._iceCandidateSubject.send(json)
        }
        
        socket.on("camera-toggled") { [weak self] data, _ in
            guard let dataArray = data as? [[String: Any]],
                  let json = dataArray.first else { return }
            self?._cameraToggledSubject.send(json)
        }
        
        socket.on("end-call") { [weak self] data, _ in
            guard let dataArray = data as? [[String: Any]],
                  let json = dataArray.first else { return }
            self?._callEndedSubject.send(json)
        }
    }
}
