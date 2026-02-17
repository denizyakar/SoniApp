//  ChatView.swift
//  SoniApp
//
//  DEĞİŞTİRİLDİ: Tarih separator + saat:dakika eklendi.
//

import SwiftUI
import SwiftData

/// Mesajlaşma ekranı.
struct ChatView: View {
    let user: ChatUser
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var viewModel = ChatViewModel()
    
    @Query private var messages: [MessageItem]
    @Environment(\.modelContext) private var context
    
    // Feature 2.5: Info sheet için seçili mesaj
    @State private var selectedMessageForInfo: MessageItem?
    
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
                                currentUserId: container.sessionStore.currentUserId
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
                .onChange(of: messages.count) { _ in
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
        .navigationTitle(user.username)
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
        HStack {
            TextField("Type a message...", text: $viewModel.text)
                .padding(12)
                .font(.system(size: 16))
                .textFieldStyle(.plain)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray), lineWidth: 1)
                    )
                .padding(.horizontal)
            
            Button(action: {
                viewModel.sendMessage()
            }) {
                Image(systemName: "paperplane.fill")
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.blue)
                    .clipShape(Circle())
            }
            .padding(.trailing)
            .disabled(viewModel.text.isEmpty)
        }
        .padding(.bottom)
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
struct MessageBubble: View {
    let message: MessageItem
    let currentUserId: String?
    
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
        HStack {
            if isFromMe { Spacer() }
            
            VStack(alignment: isFromMe ? .trailing : .leading, spacing: 2) {
                // Sender name — sadece karşıdan gelen mesajlarda göster
                if !isFromMe && !message.senderName.isEmpty {
                    Text(message.senderName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }
                
                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.top, isFromMe || message.senderName.isEmpty ? 8 : 2)
                    .padding(.bottom, 2)
                
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
                        if isFromMe && message.isRead, let readAt = message.readAt {
                            Text("· Read, \(MessageDateFormatter.timeString(from: readAt))")
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
