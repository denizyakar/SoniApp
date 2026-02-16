//  ChatView.swift
//  SoniApp
//
//  DEĞİŞTİRİLDİ: DependencyContainer entegrasyonu. UI AYNI KALDI.
//

import SwiftUI
import SwiftData

/// Mesajlaşma ekranı.
///
/// **Ne değişti?**
/// UI tasarımı AYNI KALDI — kullanıcı hiçbir fark görmeyecek.
///
/// İç yapıda:
/// - ViewModel artık empty init + setup() pattern kullanıyor
/// - `AuthManager.shared.currentUserId` → `container.sessionStore.currentUserId`
/// - `AuthManager.shared.currentChatPartnerId` → `container.sessionStore`
/// - `MessageBubble` artık `userId` parametresi alıyor
struct ChatView: View {
    let user: ChatUser
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var viewModel = ChatViewModel()
    
    @Query private var messages: [MessageItem]
    @Environment(\.modelContext) private var context
    
    init(user: ChatUser) {
        self.user = user
        
        // @Query init'te yapılandırılmalı (SwiftUI kısıtı).
        // SessionStore henüz erişilebilir değil, UserDefaults'tan doğrudan okuyoruz.
        // Bu, @Query'nin init requirement'ı nedeniyle kaçınılmaz bir trade-off.
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
                    LazyVStack {
                        ForEach(messages) { message in
                            MessageBubble(
                                message: message,
                                currentUserId: container.sessionStore.currentUserId
                            )
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
            }
            
            inputArea
        }
        .navigationTitle(user.username)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Container'dan gerçek servisleri inject et
            viewModel.setup(
                user: user,
                context: context,
                chatService: container.chatService,
                sessionStore: container.sessionStore
            )
            container.sessionStore.currentChatPartnerId = user.id
        }
        .onDisappear {
            container.sessionStore.currentChatPartnerId = nil
        }
    }
    
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

/// Mesaj baloncuğu.
///
/// **Ne değişti?**
/// `message.isFromCurrentUser` (AuthManager.shared bağımlı) →
/// `message.isFromCurrentUser(userId:)` (parametre olarak alıyor)
struct MessageBubble: View {
    let message: MessageItem
    let currentUserId: String?
    
    private var isFromMe: Bool {
        message.isFromCurrentUser(userId: currentUserId)
    }
    
    var body: some View {
        HStack {
            if isFromMe { Spacer() }
            
            Text(message.text)
                .padding()
                .background(isFromMe ? Color.blue : Color(.systemGray))
                .foregroundColor(isFromMe ? .white : .black)
                .cornerRadius(12)
                .frame(maxWidth: 250, alignment: isFromMe ? .trailing : .leading)
            
            if !isFromMe { Spacer() }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .id(message.id)
    }
}
