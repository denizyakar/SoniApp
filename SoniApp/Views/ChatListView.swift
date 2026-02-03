//
//  ChatListView.swift
//  SoniApp
//
//  Created by Ali Deniz Yakar on 25.01.2026.
//

import SwiftUI
import SwiftData

struct ChatListView: View {
    @StateObject private var viewModel = ChatListViewModel()
    
    // Read users from swiftdata
    @Query private var users: [UserItem]
    
    @Environment(\.modelContext) private var context
    
    var body: some View {
        NavigationStack {
            List(users) { user in
                
                // ChatView wants struct
                // Changing UserItem to struct and sending it
                let chatUserStruct = ChatUser(id: user.id, username: user.username)
                
                NavigationLink(destination: ChatView(user: chatUserStruct)) {
                    HStack {
                        Image(systemName: user.avatarName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                            .padding(.trailing, 8)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading) {
                            Text(user.username)
                                .font(.headline)
                            
                            Text("Click to start chatting")
                                .font(.footnote)
                                .foregroundColor(Color(.systemGray))
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Messages")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Logout") {
                        AuthManager.shared.logout()
                    }
                    .foregroundColor(.red)
                }
            }
            .onAppear {
                // Grant database permissions to the ViewModel and check the server.
                viewModel.setup(context: context)
            }
        }
    }
}

// Testing purposes, might crash:

/*

#Preview {
    // Virtual Database
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: UserItem.self, configurations: config)
    
    let user1 = UserItem(id: "1", username: "PreviewUser")
    let user2 = UserItem(id: "2", username: "PreviewUser2")
    let user3 = UserItem(id: "3", username: "PreviewUser3")
    
    container.mainContext.insert(user1)
    container.mainContext.insert(user2)
    container.mainContext.insert(user3)
    
    // Appearance (Light and Dark Theme side by side)
    return VStack(spacing: 0) {
        // Light mode
        ChatListView()
            .environment(\.colorScheme, .light)
            .previewDisplayName("Light Mode")
        
        Divider().background(Color.red) // divider line
        
        // Dark mode
        ChatListView()
            .environment(\.colorScheme, .dark)
            .previewDisplayName("Dark Mode")
    }
    .modelContainer(container) // connecting virtual database
}

*/
