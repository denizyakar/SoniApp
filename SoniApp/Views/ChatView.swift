//
//  ContentView.swift
//  SoniApp
//
//  Created by Ali Deniz Yakar on 24.01.2026.
//

import SwiftUI
import SwiftData

struct ChatView: View {
    let user: ChatUser
    @StateObject private var viewModel = ChatViewModel()
    
    // SWIFTDATA MAGIC 🪄
    // Automatically fetch messages from local DB and update UI on change
    @Query private var messages: [MessageItem]
    
    // Environment context to pass to ViewModel for saving data
    @Environment(\.modelContext) private var context
    
    init(user: ChatUser) {
        self.user = user
        
        // CONSTRUCT QUERY:
        // "Fetch messages where (Sender is Me AND Receiver is Friend) OR (Sender is Friend AND Receiver is Me)"
        // "Sort by Date"
        let myId = AuthManager.shared.currentUserId ?? ""
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
                        // Iterating over SwiftData items directly
                        ForEach(messages) { message in
                            MessageBubble(message: message)
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
            // Inject user and database context into ViewModel
            viewModel.setup(user: user, context: context)
        }
    }
    
    var inputArea: some View {
        HStack {
            TextField("Type a message...", text: $viewModel.text)
                .textFieldStyle(.roundedBorder)
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

// Update Bubble to accept MessageItem (Class) instead of Message (Struct)
struct MessageBubble: View {
    let message: MessageItem
    
    var body: some View {
        HStack {
            if message.isFromCurrentUser { Spacer() }
            
            Text(message.text)
                .padding()
                .background(message.isFromCurrentUser ? Color.blue : Color(.systemGray5))
                .foregroundColor(message.isFromCurrentUser ? .white : .black)
                .cornerRadius(12)
                .frame(maxWidth: 250, alignment: message.isFromCurrentUser ? .trailing : .leading)
            
            if !message.isFromCurrentUser { Spacer() }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .id(message.id)
    }
}

#Preview {
    ChatView(user: ChatUser(id: "test_id", username: "Deneme Kullanıcısı"))
}
