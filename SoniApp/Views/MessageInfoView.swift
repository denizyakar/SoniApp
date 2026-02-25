//
//  MessageInfoView.swift
//  SoniApp
//
//  Message detail screen — opens as half-sheet.
//  Shows send date, read status, and message text.
//

import SwiftUI

/// Message detail screen opened via long press → Info button.
struct MessageInfoView: View {
    let message: MessageItem
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                // Mesaj metni
                Section {
                    Text(message.text)
                        .font(.body)
                        .foregroundColor(AppTheme.white)
                } header: {
                    Text("Message")
                        .foregroundColor(AppTheme.secondaryText)
                }
                .listRowBackground(AppTheme.backgroundLight)
                
                // Send date
                Section {
                    HStack {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(AppTheme.white)
                        Text(formattedDate(message.date))
                            .foregroundColor(AppTheme.white)
                    }
                } header: {
                    Text("Sent")
                        .foregroundColor(AppTheme.secondaryText)
                }
                .listRowBackground(AppTheme.backgroundLight)
                
                // Okunma durumu
                Section {
                    if message.isRead, let readAt = message.readAt {
                        HStack {
                            Image(systemName: "eye.fill")
                                .foregroundColor(.green)
                            Text("Read, \(formattedDate(readAt))")
                                .foregroundColor(AppTheme.white)
                        }
                    } else {
                        HStack {
                            Image(systemName: "eye.slash")
                                .foregroundColor(AppTheme.secondaryText)
                            Text("Not read yet")
                                .foregroundColor(AppTheme.secondaryText)
                        }
                    }
                } header: {
                    Text("Read Status")
                        .foregroundColor(AppTheme.secondaryText)
                }
                .listRowBackground(AppTheme.backgroundLight)
                
                // Sender
                if !message.senderName.isEmpty {
                    Section {
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(AppTheme.white)
                            Text(message.senderName)
                                .foregroundColor(AppTheme.white)
                        }
                    } header: {
                        Text("Sender")
                            .foregroundColor(AppTheme.secondaryText)
                    }
                    .listRowBackground(AppTheme.backgroundLight)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Message Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.white)
                }
            }
        }
    }
    
    /// Full date format: "Feb 16, 2026 at 17:30"
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' HH:mm"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: date)
    }
}

#Preview {
    MessageInfoView(
        message: MessageItem(
            id: "preview-1",
            text: "Hey, how are you?",
            senderId: "user1",
            receiverId: "user2",
            date: Date(),
            senderName: "Ali",
            isRead: true,
            readAt: Date()
        )
    )
}
