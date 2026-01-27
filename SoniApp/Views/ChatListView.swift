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
    
    // SWIFTDATA MAGIC 🪄 (Kullanıcıları Diskten Oku)
    @Query private var users: [UserItem]
    
    @Environment(\.modelContext) private var context
    
    var body: some View {
        NavigationStack {
            List(users) { user in // Artık UserItem listesi dönüyor
                
                // DİKKAT: ChatView bizden 'ChatUser' (Struct) istiyor.
                // Veritabanı objesini (UserItem) -> Struct'a çevirip yolluyoruz.
                let chatUserStruct = ChatUser(id: user.id, username: user.username)
                
                NavigationLink(destination: ChatView(user: chatUserStruct)) {
                    HStack {
                        Image(systemName: user.avatarName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 40, height: 40)
                            .padding(.trailing, 5)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading) {
                            Text(user.username)
                                .font(.headline)
                            
                            Text("Click to start chatting")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.vertical, 5)
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
                // ViewModel'e veritabanı yetkisini ver ve sunucuyu kontrol et
                viewModel.setup(context: context)
            }
        }
    }
}

#Preview {
    ChatListView()
}
