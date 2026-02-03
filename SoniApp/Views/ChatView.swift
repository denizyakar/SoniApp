//  ChatView.swift
//  SoniApp
//
//  Created by Ali Deniz Yakar on 24.01.2026.
//

import SwiftUI
import SwiftData

struct ChatView: View {
    let user: ChatUser
    @StateObject private var viewModel = ChatViewModel()
    
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

// Update Bubble to accept MessageItem (Class) instead of Message (Struct)
struct MessageBubble: View {
    let message: MessageItem
    
    var body: some View {
        HStack {
            if message.isFromCurrentUser { Spacer() }
            
            Text(message.text)
                .padding()
                .background(message.isFromCurrentUser ? Color.blue : Color(.systemGray))
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
    // Virtual database
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: MessageItem.self, configurations: config)
    
    let myPreviewId = "my_test_id"
    let partnerId = "other_user_id"
    
    UserDefaults.standard.set("fake_token", forKey: "authToken")
    UserDefaults.standard.set(myPreviewId, forKey: "userId") // AuthManager knows my id from here
    AuthManager.shared.currentUserId = myPreviewId
    
    // Create messages
    // Note: receiverId and senderId must match.
    
    // Message 1: I sent
    let msg1 = MessageItem(
        id: "1",
        text: "Hi, how is it going?",
        senderId: myPreviewId,
        receiverId: partnerId,
        date: Date()
    )
    
    // Message 2: They sent
    let msg2 = MessageItem(
        id: "2",
        text: "It's going well, how about you?",
        senderId: partnerId,
        receiverId: myPreviewId,
        date: Date()
    )
    
    // Message 3: I answered
    let msg3 = MessageItem(
        id: "3",
        text: "Good, thanks.",
        senderId: myPreviewId,
        receiverId: partnerId,
        date: Date()
    )
    
    // Add to virtual database
    container.mainContext.insert(msg1)
    container.mainContext.insert(msg2)
    container.mainContext.insert(msg3)
    
    // Other user
    let chatPartner = ChatUser(id: partnerId, username: "Test Friend")
    
    // Draw the view
    return VStack(spacing: 0) {
        
        // Light mode
        NavigationStack { // wrapping to navigation be seen
            ChatView(user: chatPartner)
        }
        .environment(\.colorScheme, .light)
        .previewDisplayName("Light Mode")
        
        Divider().background(Color.red)
        
        // Dark mode
        NavigationStack {
            ChatView(user: chatPartner)
        }
        .environment(\.colorScheme, .dark)
        .previewDisplayName("Dark Mode")
    }
    .modelContainer(container)
}

