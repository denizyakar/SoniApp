//
//  ChatListView.swift
//  SoniApp
//
//  DEĞİŞTİRİLDİ: DependencyContainer entegrasyonu. UI AYNI KALDI.
//

import SwiftUI
import SwiftData

/// Kullanıcı listesi ekranı.
///
/// **Ne değişti?**
/// UI tasarımı AYNI KALDI — kullanıcı hiçbir fark görmeyecek.
struct ChatListView: View {
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var viewModel = ChatListViewModel()
    
    @Query private var users: [UserItem]
    @Environment(\.modelContext) private var context
    
    var body: some View {
        NavigationStack {
            List(users.filter { $0.id != container.sessionStore.currentUserId }) { user in
                
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
                        container.makeAuthService().logout()
                    }
                    .foregroundColor(.red)
                }
            }
            .onAppear {
                viewModel.setup(
                    context: context,
                    authService: container.makeAuthService(),
                    chatService: container.chatService
                )
            }
        }
    }
}
