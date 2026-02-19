//  ChatView.swift
//  SoniApp
//
//  DEĞİŞTİRİLDİ: Tarih separator + saat:dakika eklendi.
//

import SwiftUI
import SwiftData
import UIKit

/// Mesajlaşma ekranı.
struct ChatView: View {
    let user: ChatUser
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var viewModel = ChatViewModel()
    
    @Query private var messages: [MessageItem]
    @Environment(\.modelContext) private var context
    
    // Feature 2.5: Info sheet için seçili mesaj
    @State private var selectedMessageForInfo: MessageItem?
    
    // Feature 3: Photo Sharing
    @State private var showImagePicker = false
    @State private var inputImage: UIImage?
    
    init(user: ChatUser) {
        self.user = user
        
        let myId = UserDefaults.standard.string(forKey: "userId") ?? ""
        let otherId = user.id
        
        let predicate = #Predicate<MessageItem> { msg in
            (msg.senderId == myId && msg.receiverId == otherId) ||
            (msg.senderId == otherId && msg.receiverId == myId)
        }
        
        _messages = Query(filter: predicate, sort: \.date)
    }
    
    var body: some View {
        VStack {
            // Message List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            
                            // Date Separator — gün değiştiğinde araya tarih yazısı
                            if shouldShowDateSeparator(at: index) {
                                DateSeparatorView(date: message.date)
                                    .padding(.vertical, 8)
                            }
                            
                            MessageBubble(
                                message: message,
                                currentUserId: container.sessionStore.currentUserId,
                                senderDisplayName: user.displayName,
                                senderAvatar: user.avatar,
                                senderAvatarUrl: user.avatarImageUrl
                            )
                            .contextMenu {
                                Button(role: .destructive) {
                                    viewModel.deleteMessage(id: message.id)
                                } label: {
                                    Label("Delete from me", systemImage: "trash")
                                }
                                
                                Button {
                                    selectedMessageForInfo = message
                                } label: {
                                    Label("Info", systemImage: "info.circle")
                                }
                            }
                        }
                    }
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastId = messages.last?.id {
                         withAnimation {
                             proxy.scrollTo(lastId, anchor: .bottom)
                         }
                    }
                }
                .onAppear {
                    // Chat açıldığında en son mesaja scroll et
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let lastId = messages.last?.id {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            
            inputArea
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    AvatarView(chatUser: user, size: 28)
                    Text(user.displayName)
                        .font(.headline)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedMessageForInfo) { message in
            MessageInfoView(message: message)
                .presentationDetents([.medium])
        }
        .onAppear {
            viewModel.setup(
                user: user,
                context: context,
                chatService: container.chatService,
                sessionStore: container.sessionStore
            )
            container.sessionStore.currentChatPartnerId = user.id
            container.sessionStore.isInChatList = false  // Chat açıldı, artık ChatList'te değiliz
            container.sessionStore.clearUnread(for: user.id)  // Okunmamış mesaj badge'ini temizle
            
            // Pending mesajları tetikle — chat'e girince hemen retry
            container.retryService.retryAllPendingMessages()
        }
        .onDisappear {
            container.sessionStore.currentChatPartnerId = nil
            container.sessionStore.isInChatList = true  // Chat'ten çıkınca ChatList'e dönüyoruz
        }
    }
    
    // MARK: - Date Separator Logic
    
    /// İlk mesajda her zaman separator göster.
    /// Sonraki mesajlarda, önceki mesajla farklı günse separator göster.
    private func shouldShowDateSeparator(at index: Int) -> Bool {
        if index == 0 { return true }
        
        let currentDate = messages[index].date
        let previousDate = messages[index - 1].date
        return !MessageDateFormatter.isSameDay(currentDate, previousDate)
    }
    
    // MARK: - Input Area
    
    var inputArea: some View {
        VStack(spacing: 0) {
            // Preview Area (Varsa)
            if let image = inputImage {
                HStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .cornerRadius(8)
                        .clipped()
                        .overlay(
                            Button(action: {
                                withAnimation {
                                    inputImage = nil
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.gray)
                                    .background(Color.white)
                                    .clipShape(Circle())
                            }
                            .offset(x: 5, y: -5),
                            alignment: .topTrailing
                        )
                        .padding(4)
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
                .transition(.opacity) // Fade in/out
            }
            
            HStack {
                // Camera Button
                Button(action: {
                    showImagePicker = true
                }) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color(.systemGray))
                        .padding(.leading, 12)
                }
                .sheet(isPresented: $showImagePicker) {
                    ImagePicker(image: $inputImage)
                }
                // .onChange kaldırıldı — artık hemen göndermiyoruz
                
                TextField("Type a message...", text: $viewModel.text, axis: .vertical) // axis: .vertical ile çok satırlı destek
                    .padding(10)
                    .font(.system(size: 16))
                    .textFieldStyle(.plain)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                    .padding(.horizontal, 8)
                
                Button(action: {
                    // Hem resim hem yazı gönder
                    viewModel.sendMessage(image: inputImage)
                    // Resmi temizle (yazıyı ViewModel temizliyor)
                    withAnimation {
                        inputImage = nil
                    }
                }) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 20)) // İkon boyutu
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.blue)
                        .clipShape(Circle())
                }
                .padding(.trailing, 12)
                // Disable durumu: Hem yazı boş hem resim yoksa disable
                .disabled(viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && inputImage == nil)
                .opacity((viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && inputImage == nil) ? 0.6 : 1.0)
            }
            .padding(.bottom, 8)
        }
        .background(Color(.systemBackground)) // Klavye arkası
    }
}

// MARK: - Date Separator View

/// Gün değişimlerinde mesajlar arasına eklenen tarih etiketi.
/// WhatsApp tarzı: "Today", "Yesterday", "Monday", "Feb 6"
struct DateSeparatorView: View {
    let date: Date
    
    var body: some View {
        Text(MessageDateFormatter.daySeparatorString(from: date))
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color(.systemGray6))
            )
    }
}

// MARK: - Message Bubble

/// Mesaj baloncuğu — tüm özellikler: saat, isim, read receipt, offline status.
/// Mesaj baloncuğu — tüm özellikler: saat, isim, avatar, read receipt, offline status.
struct MessageBubble: View {
    let message: MessageItem
    let currentUserId: String?
    let senderDisplayName: String  // nickname varsa o, yoksa senderName
    let senderAvatar: String       // SF Symbol adı
    let senderAvatarUrl: URL?      // Fotoğraf URL'si (varsa)
    
    private var isFromMe: Bool {
        message.isFromCurrentUser(userId: currentUserId)
    }
    
    /// Offline queue — failed mesajlar soluk renkte
    private var bubbleColor: Color {
        if isFromMe {
            return message.status == .failed ? Color.gray : Color.blue
        } else {
            return Color(.systemGray5)
        }
    }
    
    /// Failed mesajlar yarı saydam
    private var bubbleOpacity: Double {
        message.status == .failed ? 0.6 : 1.0
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isFromMe { Spacer() }
            
            // Avatar — sadece karşıdan gelen mesajlarda
            if !isFromMe {
                AvatarView(
                    imageUrl: senderAvatarUrl,
                    sfSymbol: senderAvatar,
                    size: 28
                )
            }
            
            VStack(alignment: isFromMe ? .trailing : .leading, spacing: 2) {
                // Sender name — sadece karşıdan gelen mesajlarda göster
                if !isFromMe && !senderDisplayName.isEmpty {
                    Text(senderDisplayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }
                
                // Mesaj İçeriği: Resim ve/veya Metin
                VStack(alignment: .leading, spacing: 4) {
                    // Resim varsa göster
                    if let imageUrl = message.imageUrl, !imageUrl.isEmpty {
                        // URL Oluşturma: Local file (pending) veya Remote URL
                        let url: URL? = {
                            if imageUrl.hasPrefix("file://") {
                                return URL(string: imageUrl)
                            }
                            return URL(string: "\(APIEndpoints.baseURL)\(imageUrl)")
                        }()
                        
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            ZStack {
                                Color.gray.opacity(0.3)
                                ProgressView()
                            }
                        }
                        .frame(width: 200, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 4)
                        .padding(.horizontal, 4)
                        // Kendi mesajımsa sağa, onunki sola (gerçi bubble zaten hizalı)
                    }
                    
                    // Metin varsa göster
                    if !message.text.isEmpty {
                        Text(message.text)
                            .padding(.horizontal, 12)
                            .padding(.top, (message.imageUrl != nil) ? 4 : (isFromMe || senderDisplayName.isEmpty ? 8 : 2))
                            .padding(.bottom, 2)
                    }
                }
                
                // Alt satır: Saat + Read/Status durumu
                HStack(spacing: 4) {
                    // Failed mesaj durumu
                    if isFromMe && message.status == .failed {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                        Text("Message not sent")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    } else if isFromMe && message.status == .pending {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.7))
                    } else {
                        Text(MessageDateFormatter.timeString(from: message.date))
                            .font(.system(size: 11))
                            .foregroundColor(isFromMe ? .white.opacity(0.7) : .gray)
                        
                        // "Read, 13:30" — sadece kendi mesajlarımda, okunduysa
                        if isFromMe && message.isRead, message.readAt != nil {
                            Text("· Read")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }
            .background(bubbleColor)
            .foregroundColor(isFromMe ? .white : .primary)
            .opacity(bubbleOpacity)
            .cornerRadius(16)
            .frame(maxWidth: 280, alignment: isFromMe ? .trailing : .leading)
            
            if !isFromMe { Spacer() }
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
        .id(message.id)
    }
}
