//
//  ChatListView.swift
//  ChatApp
//
//  Created by Ali Deniz Yakar on 25.01.2026.
//

import SwiftUI

struct ChatListView: View {
    @StateObject private var viewModel = ChatListViewModel()
    
    var body: some View {
        // NavigationStack: Allows moving between screens (Push/Pop)
        NavigationStack {
            List(viewModel.users) { user in
                
                // NavigationLink: Makes the row clickable
                // destination: Where do we go? -> ChatView
                NavigationLink(destination: ChatView(user: user)) {
                    
                    // Row Design (Your design logic)
                    HStack {
                        Image(systemName: user.avatarName) // Using system icons for now
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 40, height: 40)
                            .padding(.trailing, 5)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading) {
                            Text(user.name)
                                .font(.headline)
                            
                            Text("Click to start chatting")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
            .navigationTitle("Messages") // Top bar title
        }
    }
}

#Preview {
    ChatListView()
}
