//  ChatView.swift
//  SoniApp

import SwiftUI
import SwiftData
import UIKit

/// Chat screen.
struct ChatView: View {
    let user: ChatUser
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var viewModel = ChatViewModel()
    
    @Query private var messages: [MessageItem]
    @Environment(\.modelContext) private var context
    
    // Selected message for info sheet
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
                            
                            // Date Separator — insert date label between days
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
                    // Scroll to latest message when chat opens
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let lastId = messages.last?.id {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            
            inputArea
        }
        .background(AppTheme.background.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    AvatarView(chatUser: user, size: 28)
                    Text(user.displayName)
                        .font(.headline)
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    if let userId = container.sessionStore.currentUserId,
                       let username = container.sessionStore.currentUsername {
                        container.callManager.startCall(
                            to: user.id,
                            callerId: userId,
                            callerName: container.sessionStore.currentDisplayName,
                            callerAvatar: container.sessionStore.currentAvatarImageUrl?.absoluteString ?? "",
                            calleeName: user.displayName,
                            calleeAvatar: user.avatarImageUrl?.absoluteString ?? ""
                        )
                    }
                }) {
                    Image(systemName: "video.fill")
                        .foregroundColor(AppTheme.white)
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
            container.sessionStore.isInChatList = false  // Chat opened, no longer in ChatList
            container.sessionStore.clearUnread(for: user.id)  // Clear unread badge
            
            // Retry pending messages on chat open
            container.retryService.retryAllPendingMessages()
        }
        .onDisappear {
            container.sessionStore.currentChatPartnerId = nil
            container.sessionStore.isInChatList = true  // Returning to ChatList
        }
    }
    
    // MARK: - Date Separator Logic
    
    /// Always show separator for the first message.
    /// For subsequent messages, show separator if on a different day.
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
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.primary)
                        .padding(8)
                        .background(AppTheme.white.opacity(0.85))
                        .clipShape(Circle())
                        .padding(.leading, 8)
                }
                .sheet(isPresented: $showImagePicker) {
                    ImagePicker(image: $inputImage)
                }
                // .onChange removed — no longer sending immediately
                
                TextField("", text: $viewModel.text, prompt: Text("Type a message...")
                    .foregroundColor(AppTheme.white), axis: .vertical) // axis: .vertical for multi-line support
                    .padding(10)
                    .font(.system(size: 16))
                    .textFieldStyle(.plain)
                    .foregroundColor(AppTheme.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(AppTheme.inputBorder, lineWidth: 2)
                    )
                    
                
                Button(action: {
                    // Send both image and text
                    viewModel.sendMessage(image: inputImage)
                    // Clear image (text is cleared by ViewModel)
                    withAnimation {
                        inputImage = nil
                    }
                }) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 20)) // Icon size
                        .foregroundColor(AppTheme.primary)
                        .padding(10)
                        .background(AppTheme.white)
                        .clipShape(Circle())
                }
                .padding(.trailing, 12)
                // Disabled when both text is empty and no image selected
                .disabled(viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && inputImage == nil)
                .opacity((viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && inputImage == nil) ? 0.6 : 1.0)
            }
            .padding(.bottom, 8)
        }
        .background(AppTheme.background)
    }
}

// MARK: - Date Separator View

/// Date label inserted between messages when the day changes.
/// WhatsApp style: "Today", "Yesterday", "Monday", "Feb 6"
struct DateSeparatorView: View {
    let date: Date
    
    var body: some View {
        Text(MessageDateFormatter.daySeparatorString(from: date))
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(AppTheme.secondaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(AppTheme.dateBadge)
            )
    }
}

// MARK: - Message Bubble

/// Message bubble — time, name, avatar, read receipt, offline status.
struct MessageBubble: View {
    let message: MessageItem
    let currentUserId: String?
    let senderDisplayName: String  // nickname if available, otherwise senderName
    let senderAvatar: String       // SF Symbol name
    let senderAvatarUrl: URL?      // Profile photo URL (if any)
    
    private var isFromMe: Bool {
        message.isFromCurrentUser(userId: currentUserId)
    }
    
    /// Offline queue — failed messages shown dimmed
    private var bubbleColor: Color {
        if isFromMe {
            return message.status == .failed ? Color.gray : AppTheme.myBubble
        } else {
            return AppTheme.incomingBubble
        }
    }
    
    /// Failed messages are semi-transparent
    private var bubbleOpacity: Double {
        message.status == .failed ? 0.6 : 1.0
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isFromMe { Spacer() }
            
            // Avatar — only for incoming messages
            if !isFromMe {
                AvatarView(
                    imageUrl: senderAvatarUrl,
                    sfSymbol: senderAvatar,
                    size: 28
                )
            }
            
            VStack(alignment: isFromMe ? .trailing : .leading, spacing: 2) {
                // Sender name — only for incoming messages
                if !isFromMe && !senderDisplayName.isEmpty {
                    Text(senderDisplayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.white)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }
                
                // Message Content: Image and/or Text
                VStack(alignment: .leading, spacing: 4) {
                    // Show image if available
                    if let imageUrl = message.imageUrl, !imageUrl.isEmpty {
                        // URL: Local file (pending) or Remote URL
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
                        // Alignment (bubble already handles this)
                    }
                    
                    // Show text if available
                    if !message.text.isEmpty {
                        Text(message.text)
                            .padding(.horizontal, 12)
                            .padding(.top, (message.imageUrl != nil) ? 4 : (isFromMe || senderDisplayName.isEmpty ? 8 : 2))
                            .padding(.bottom, 2)
                    }
                }
                
                // Bottom row: Time + Read/Status
                HStack(spacing: 4) {
                    // Failed message status
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
                            .foregroundColor(isFromMe ? .white.opacity(0.7) : .white.opacity(0.7))
                        
                        // "Read" — only my messages, when read
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
            .foregroundColor(.white)
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

#Preview("Chat - Full") {
    let mockUser = ChatUser(
        id: "mock-user-1",
        username: "kankiii",
        nickname: "Kankam",
        avatarName: "star.circle.fill",
        avatarUrl: nil
    )
    
    NavigationStack {
        ChatView(user: mockUser)
    }
    .environmentObject(DependencyContainer())
    .modelContainer(for: MessageItem.self, inMemory: true)
}

#Preview("Message Bubbles") {
    let myId = "me"
    
    VStack(spacing: 8) {
        MessageBubble(
            message: MessageItem(id: "1", text: "Selam kanka!", senderId: myId, receiverId: "other", date: Date()),
            currentUserId: myId,
            senderDisplayName: "",
            senderAvatar: "person.circle",
            senderAvatarUrl: nil
        )
        
        MessageBubble(
            message: MessageItem(id: "2", text: "Hey, how are you?", senderId: "other", receiverId: myId, date: Date()),
            currentUserId: myId,
            senderDisplayName: "Kankam",
            senderAvatar: "star.circle.fill",
            senderAvatarUrl: nil
        )
        
        MessageBubble(
            message: MessageItem(id: "3", text: "Good, you?", senderId: myId, receiverId: "other", date: Date(), isRead: true, readAt: Date()),
            currentUserId: myId,
            senderDisplayName: "",
            senderAvatar: "person.circle",
            senderAvatarUrl: nil
        )
    }
    .padding()
    .background(AppTheme.background)
}
