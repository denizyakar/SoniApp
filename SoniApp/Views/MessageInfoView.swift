//
//  MessageInfoView.swift
//  SoniApp
//
//  Mesaj detay ekranı — half-sheet olarak açılır.
//  Gönderilme tarihi, okunma durumu, mesaj metni gösterir.
//

import SwiftUI

/// Long press → Info butonuyla açılan mesaj detay ekranı.
struct MessageInfoView: View {
    let message: MessageItem
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                // Mesaj metni
                Section("Message") {
                    Text(message.text)
                        .font(.body)
                }
                
                // Gönderilme tarihi
                Section("Sent") {
                    HStack {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(.blue)
                        Text(formattedDate(message.date))
                    }
                }
                
                // Okunma durumu
                Section("Read Status") {
                    if message.isRead, let readAt = message.readAt {
                        HStack {
                            Image(systemName: "eye.fill")
                                .foregroundColor(.green)
                            Text("Read, \(formattedDate(readAt))")
                        }
                    } else {
                        HStack {
                            Image(systemName: "eye.slash")
                                .foregroundColor(.gray)
                            Text("Not read yet")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Gönderen
                if !message.senderName.isEmpty {
                    Section("Sender") {
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(.blue)
                            Text(message.senderName)
                        }
                    }
                }
            }
            .navigationTitle("Message Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    /// Tam tarih formatı: "Feb 16, 2026 at 17:30"
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' HH:mm"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: date)
    }
}
