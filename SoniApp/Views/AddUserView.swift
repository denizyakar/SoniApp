//
//  AddUserView.swift
//  SoniApp
//
//  Search and add users to your chat list.
//

import SwiftUI

struct AddUserView: View {
    @EnvironmentObject private var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss
    
    @State private var allUsers: [ChatUser] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var addingUserId: String?
    
    /// IDs of users already in the contact list (passed from ChatListView)
    let existingContactIds: Set<String>
    
    var filteredUsers: [ChatUser] {
        let available = allUsers.filter { !existingContactIds.contains($0.id) }
        if searchText.isEmpty {
            return available
        }
        return available.filter {
            $0.username.localizedCaseInsensitiveContains(searchText) ||
            ($0.nickname?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                if isLoading {
                    ProgressView()
                        .tint(AppTheme.white)
                } else if filteredUsers.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: searchText.isEmpty ? "person.badge.plus" : "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(AppTheme.secondaryText)
                        Text(searchText.isEmpty ? "No new users to add" : "No results found")
                            .foregroundColor(AppTheme.secondaryText)
                            .font(.headline)
                    }
                } else {
                    List(filteredUsers) { user in
                        HStack {
                            AvatarView(chatUser: user, size: 44)
                                .padding(.trailing, 8)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName)
                                    .font(.headline)
                                    .foregroundColor(AppTheme.white)
                                if let nickname = user.nickname, !nickname.isEmpty, nickname != user.username {
                                    Text("@\(user.username)")
                                        .font(.footnote)
                                        .foregroundColor(AppTheme.secondaryText)
                                }
                            }
                            
                            Spacer()
                            
                            if addingUserId == user.id {
                                ProgressView()
                                    .tint(AppTheme.white)
                            } else {
                                Button {
                                    addUser(user)
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(AppTheme.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                        .listRowBackground(AppTheme.backgroundLight)
                        .listRowSeparatorTint(AppTheme.white.opacity(0.1))
                    }
                    .scrollContentBackground(.hidden)
                    .searchable(text: $searchText, prompt: "Search users")
                }
            }
            .navigationTitle("Add User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.white)
                }
            }
            .onAppear {
                fetchAllUsers()
            }
        }
    }
    
    // MARK: - Actions
    
    private func fetchAllUsers() {
        isLoading = true
        let authService = container.makeAuthService()
        authService.fetchAllUsers { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let users):
                    allUsers = users
                case .failure(let error):
                    print("❌ Fetch all users error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func addUser(_ user: ChatUser) {
        addingUserId = user.id
        
        // Use ChatListViewModel via NotificationCenter to add the contact
        let authService = container.makeAuthService()
        authService.addContact(contactId: user.id) { result in
            DispatchQueue.main.async {
                addingUserId = nil
                switch result {
                case .success:
                    // Notify ChatListViewModel to refresh
                    NotificationCenter.default.post(name: .contactAdded, object: nil)
                    dismiss()
                case .failure(let error):
                    print("❌ Add contact error: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Notification Name
extension Notification.Name {
    static let contactAdded = Notification.Name("contactAdded")
}
