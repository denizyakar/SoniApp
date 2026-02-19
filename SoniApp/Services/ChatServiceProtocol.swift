//
//  ChatServiceProtocol.swift
//  SoniApp
//
//  TAMAMEN YENİDEN YAZILDI.
//
//  Değişiklikler:
//  1. getSocket() KALDIRILDI — leaky abstraction düzeltildi
//  2. Combine Publisher eklendi — ViewModel raw socket'e erişmek zorunda değil
//  3. Singleton kaldırıldı — DependencyContainer'dan inject ediliyor
//  4. onMessageReceived callback → Combine publisher'a dönüştürüldü
//

import Foundation
import SocketIO
import Combine

// MARK: - Protocol

/// Chat servisi sözleşmesi.
///
/// **Neden `getSocket()` kaldırıldı?**
/// Eskiden `ChatViewModel` şunu yapıyordu:
/// ```swift
/// socketManager.getSocket().on("receive_message") { data, ack in ... }
/// ```
/// Bu, ViewModel'in Socket.IO'nun iç yapısını bildiği anlamına geliyordu.
/// Yarın WebSocket çözümünü değiştirmek istersen (ör. URLSessionWebSocketTask),
/// ViewModel'i baştan yazman gerekirdi.
///
/// Şimdi ViewModel sadece `messagePublisher`'ı dinliyor.
/// Alt yapı ne olursa olsun (Socket.IO, gRPC, WebSocket) ViewModel'e `Message` gelir.
/// Bu, **Dependency Inversion Principle** (SOLID'in D'si) uygulamasıdır.
protocol ChatServiceProtocol {
    /// Gelen mesajları dinlemek için Combine publisher.
    var messagePublisher: AnyPublisher<Message, Never> { get }
    
    /// Yeni kullanıcı kaydı sinyali
    var userRegisteredPublisher: AnyPublisher<Void, Never> { get }
    
    /// Okundu bilgisi geldiğinde: [mesaj ID'leri] yayını
    var messageReadPublisher: AnyPublisher<[String], Never> { get }
    
    /// Bağlantı durumu değişimi (true=connected, false=disconnected)
    var connectionStatePublisher: AnyPublisher<Bool, Never> { get }
    
    /// Profil güncellemesi: (userId, nickname, avatarName, avatarUrl)
    var profileUpdatedPublisher: AnyPublisher<(String, String, String, String), Never> { get }
    
    /// Bağlantı durumu
    var isConnected: Bool { get }
    
    func connect()
    func disconnect()
    func sendMessage(text: String, senderId: String, receiverId: String, clientId: String?, imageUrl: String?)
    
    /// Fotoğraf yükle ve URL döndür
    func uploadMessageImage(_ data: Data) async throws -> String
    
    /// Mesajları okundu olarak işaretle
    func sendReadReceipt(messageIds: [String], readerId: String)
}

// MARK: - Implementation

/// Socket.IO tabanlı chat servisi.
///
/// **Değişiklikler (eski halinden farklar):**
/// 1. `static let shared` → DI ile inject ediliyor
/// 2. `getSocket()` → kaldırıldı. ViewModel artık raw socket'e erişemez
/// 3. Closure callback'ler → Combine `PassthroughSubject` ile replace edildi
/// 4. `sendMessage` artık `senderId` parametresi alıyor — AuthManager.shared'a bağımlılık YOK
///
/// **Neden Combine PassthroughSubject?**
/// `PassthroughSubject` bir "köprü"dür: imperativ dünyadan (Socket.IO callback)
/// dekleratif dünyaya (Combine pipeline) bağlanır. Socket.IO callback'lerini
/// Combine stream'ine dönüştürmenin en temiz yolu budur.
final class SocketChatService: ChatServiceProtocol {
    
    // MARK: - Combine Subjects (iç kullanım)
    
    /// Gelen mesajları yayan subject.
    private let _messageSubject = PassthroughSubject<Message, Never>()
    
    /// Yeni kullanıcı kaydı sinyali
    private let _userRegisteredSubject = PassthroughSubject<Void, Never>()
    
    /// Okundu bilgisi sinyali: [mesaj ID'leri]
    private let _messageReadSubject = PassthroughSubject<[String], Never>()
    
    /// Bağlantı durumu sinyali
    private let _connectionStateSubject = PassthroughSubject<Bool, Never>()
    
    /// Profil güncellemesi sinyali: (userId, nickname, avatarName, avatarUrl)
    private let _profileUpdatedSubject = PassthroughSubject<(String, String, String, String), Never>()
    
    // MARK: - Public Publishers (dışarıya açılan arayüz)
    
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
    
    // MARK: - Socket.IO internals
    
    private var manager: SocketManager
    private var socket: SocketIOClient
    private(set) var isConnected: Bool = false
    
    // MARK: - Init
    
    init() {
        let url = URL(string: APIEndpoints.baseURL)!
        
        manager = SocketManager(socketURL: url, config: [
            .log(false),     // Production'da log kapatıldı (eskiden .log(true) idi)
            .compress,
            .forceWebsockets(true)  // Daha stabil bağlantı
        ])
        socket = manager.defaultSocket
        
        setupListeners()
    }
    
    // MARK: - Connection
    
    func connect() {
        guard !isConnected else { return }  // Çift bağlantı önleme
        print("[SocketService] Connecting...")
        socket.connect()
    }
    
    func disconnect() {
        socket.disconnect()
        isConnected = false
    }
    
    // MARK: - Send Message
    
    /// Mesaj gönderir.
    ///
    /// **Eski hali vs yeni hali:**
    /// Eski: `sendMessage(text:, receiverId:)` → içeride `AuthManager.shared.currentUserId` kullanıyordu
    /// Yeni: `sendMessage(text:, senderId:, receiverId:)` → dışarıdan alıyor
    ///
    /// **Neden?** Service katmanı, "kim giriş yapmış" bilgisini bilmemeli.
    /// Bu, **Information Hiding** prensibidir. Servis sadece "şu mesajı gönder" der.
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
    
    /// Mesaj görseli yükle
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
            throw PROrror(message: "Upload failed")
        }
        
        struct UploadResponse: Decodable {
            let imageUrl: String
        }
        
        let result = try JSONDecoder().decode(UploadResponse.self, from: responseData)
        return result.imageUrl
    }
    
    struct PROrror: Error { let message: String }
    
    /// Mesajları okundu olarak işaretle — server'a gönder
    func sendReadReceipt(messageIds: [String], readerId: String) {
        guard !messageIds.isEmpty else { return }
        let data: [String: Any] = [
            "messageIds": messageIds,
            "readerId": readerId
        ]
        socket.emit("mark_as_read", data)
    }
    
    /// Profil güncellemesini tüm bağlı client'lara broadcast et
    func emitProfileUpdate(userId: String, nickname: String, avatarName: String, avatarUrl: String) {
        let data: [String: Any] = [
            "userId": userId,
            "nickname": nickname,
            "avatarName": avatarName,
            "avatarUrl": avatarUrl
        ]
        socket.emit("profile_updated", data)
    }
    
    // MARK: - Private: Socket Listeners
    
    private func setupListeners() {
        // Bağlantı başarılı
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            print("[SocketService] Connected ✅")
            self?.isConnected = true
            self?._connectionStateSubject.send(true)
        }
        
        // Bağlantı koptu
        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            print("[SocketService] Disconnected ⚠️")
            self?.isConnected = false
            self?._connectionStateSubject.send(false)
        }
        
        // Yeni kullanıcı kaydı
        socket.on("user_registered") { [weak self] _, _ in
            print("[SocketService] New user registered signal received")
            self?._userRegisteredSubject.send()
        }
        
        // Yeni mesaj alındı
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
        
        // Okundu bilgisi alındı
        socket.on("read_receipt") { [weak self] data, _ in
            guard let dataArray = data as? [[String: Any]],
                  let json = dataArray.first,
                  let messageIds = json["messageIds"] as? [String] else { return }
            
            self?._messageReadSubject.send(messageIds)
        }
        
        // Profil güncellemesi alındı
        socket.on("profile_updated") { [weak self] data, _ in
            guard let dataArray = data as? [[String: Any]],
                  let json = dataArray.first,
                  let userId = json["userId"] as? String,
                  let nickname = json["nickname"] as? String,
                  let avatarName = json["avatarName"] as? String else { return }
            
            let avatarUrl = json["avatarUrl"] as? String ?? ""
            
            print("[SocketService] Profile updated for user: \(userId)")
            self?._profileUpdatedSubject.send((userId, nickname, avatarName, avatarUrl))
        }
    }
}
