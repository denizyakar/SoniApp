//
//  ContentView.swift
//  ChatApp
//
//  Created by Ali Deniz Yakar on 24.01.2026.
//

import SwiftUI

struct ChatView: View {
    // @StateObject: We own this ViewModel. It stays alive as long as the View exists.
    @StateObject private var viewModel : ChatViewModel
    
    // Custom init to receive the user from the List
        init(user: ChatUser) {
            // Initialize the StateObject with the specific user
            _viewModel = StateObject(wrappedValue: ChatViewModel(user: user))
        }
    
    var body: some View {
        VStack {
           
            // Message List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack { // LazyVStack is better for performance with many messages
                        
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                        }
                    }
                }
                // Auto-scroll to bottom when a new message arrives
                .onChange(of: viewModel.messages.count) { _ in
                    if let lastId = viewModel.messages.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
            
            // Input Area
            inputArea
        }
    }
    
    // Extracting Subviews helps keep the main body clean
    var inputArea: some View {
        HStack {
            TextField("Type a message...", text: $viewModel.currentInputText)
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
            .disabled(viewModel.currentInputText.isEmpty) // Disable if empty
        }
        .padding(.bottom)
    }
}

// A separate Subview for the Bubble to keep code organized
struct MessageBubble: View {
    let message: Message
    
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
        .id(message.id) // Important for auto-scroll
    }
}

#Preview {
    ChatView(user: ChatUser(name: "Mal Efe", avatarName: "person.circle"))
}
