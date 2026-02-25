//
//  UserProfileView.swift
//  SoniApp
//
//  User profile screen: avatar selection (gallery + SF Symbol) and nickname editing.
//

import SwiftUI
import SwiftUI
// import PhotosUI - No longer needed

struct UserProfileView: View {
    @EnvironmentObject private var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss
    
    @State private var nickname: String = ""
    @State private var selectedAvatar: String = "person.circle"
    
    // Photo picker states (for ImagePicker)
    @State private var showImagePicker = false
    @State private var inputImage: UIImage?
    @State private var selectedImageData: Data?
    @State private var avatarUrl: String = "" // Server'dan gelen URL string
    
    @State private var isSaving = false
    @State private var statusMessage = ""
    
    /// Available avatar options (SF Symbols)
    let avatarOptions = [
        "person.circle", "person.circle.fill",
        "face.smiling", "face.smiling.inverse",
        "star.circle", "star.circle.fill",
        "heart.circle", "heart.circle.fill",
        "moon.circle", "moon.circle.fill",
        "sun.max.circle", "sun.max.circle.fill",
        "flame.circle", "flame.circle.fill",
        "bolt.circle", "bolt.circle.fill",
        "leaf.circle", "leaf.circle.fill",
        "pawprint.circle", "pawprint.circle.fill",
        "gamecontroller", "headphones.circle",
        "music.note", "guitars"
    ]
    
    var body: some View {
        NavigationView {
            Form {
                // MARK: - Avatar Preview & Selection
                Section {
                    VStack {
                        // Large preview
                        if let data = selectedImageData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(AppTheme.primary, lineWidth: 2))
                        } else if !avatarUrl.isEmpty {
                            AsyncImage(url: URL(string: "\(APIEndpoints.baseURL)\(avatarUrl)")) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(AppTheme.primary, lineWidth: 2))
                        } else {
                            Image(systemName: selectedAvatar)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 100, height: 100)
                                .foregroundColor(AppTheme.white)
                        }
                        
                        Button {
                            showImagePicker = true
                        } label: {
                            Label("Select Photo", systemImage: "photo.on.rectangle")
                                .font(.headline)
                                .padding(.vertical, 4)
                                .foregroundColor(AppTheme.white)
                        }
                        .padding(.top, 8)
                        .sheet(isPresented: $showImagePicker) {
                            ImagePicker(image: $inputImage)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .onChange(of: inputImage) { _, newImage in
                        if let newImage = newImage {
                            if let data = newImage.jpegData(compressionQuality: 0.8) {
                                if let compressed = processImage(data: data) {
                                    selectedImageData = compressed
                                }
                            }
                        }
                    }
                    
                    if selectedImageData != nil || !avatarUrl.isEmpty {
                        Button(role: .destructive) {
                            selectedImageData = nil
                            avatarUrl = ""
                            selectedAvatar = "person.circle"
                        } label: {
                            Label("Remove Photo", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(avatarOptions, id: \.self) { avatar in
                            Image(systemName: avatar)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 32, height: 32)
                                .foregroundColor(selectedAvatar == avatar ? AppTheme.primary : AppTheme.white)
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedAvatar == avatar ? AppTheme.secondaryText.opacity(0.6) : Color.clear)
                                )
                                .onTapGesture {
                                    selectedAvatar = avatar
                                    selectedImageData = nil
                                    avatarUrl = ""
                                }
                        }
                    }
                    .padding(.top, 8)
                } header: {
                    Text("Avatar")
                        .foregroundColor(AppTheme.white)
                }
                .listRowBackground(AppTheme.backgroundLight)
                .listRowSeparator(.hidden)
                
                // MARK: - Nickname
                Section {
                    TextField("", text: $nickname, prompt: Text("Enter nickname").foregroundColor(AppTheme.secondaryText))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .foregroundColor(AppTheme.white)
                    
                    Text("This will be displayed instead of your username.")
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                } header: {
                    Text("Nickname")
                        .foregroundColor(AppTheme.white)
                }
                .listRowBackground(AppTheme.backgroundLight)
                
                // MARK: - Bilgi
                Section {
                    HStack {
                        Text("Username")
                            .foregroundColor(AppTheme.secondaryText)
                        Spacer()
                        Text(container.sessionStore.currentUsername ?? "—")
                            .foregroundColor(AppTheme.white)
                    }
                }
                .listRowBackground(AppTheme.backgroundLight)
                
                // MARK: - Kaydet
                Section {
                    Button(action: saveProfile) {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("Save")
                                    .fontWeight(.semibold)
                                    .foregroundColor(AppTheme.white)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSaving)
                    
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(statusMessage.contains("✅") ? .green : .red)
                    }
                }
                .listRowBackground(AppTheme.backgroundLight)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppTheme.white)
                }
            }
            .onAppear {
                // Load current values
                nickname = container.sessionStore.currentNickname ?? ""
                selectedAvatar = container.sessionStore.currentAvatarName ?? "person.circle"
                avatarUrl = container.sessionStore.currentAvatarUrl ?? ""
            }
        }
    }
    
    // MARK: - Helpers
    
    /// Resize and compress photo (~30-80KB target)
    private func processImage(data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        
        // 1. Resize (256x256 max)
        let maxSize: CGFloat = 256
        let scale = maxSize / max(image.size.width, image.size.height)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        // 2. Compress (JPEG 0.75)
        return resizedImage.jpegData(compressionQuality: 0.75)
    }
    
    // MARK: - Save (Multipart)
    
    private func saveProfile() {
        guard let userId = container.sessionStore.currentUserId else { return }
        
        isSaving = true
        statusMessage = ""
        
        // Build multipart request
        let url = APIEndpoints.updateProfile(userId: userId)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // 1. Nickname field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"nickname\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(nickname)\r\n".data(using: .utf8)!)
        
        // 2. AvatarName field (SF Symbol)
        // If photo exists, also send avatarName but priority is URL
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"avatarName\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(selectedAvatar)\r\n".data(using: .utf8)!)
        
        // 3. File (Varsa)
        if let imageData = selectedImageData {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"avatarFile\"; filename=\"avatar.jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)
        } else {
             // If no photo (using SF Symbol), send empty string to clear URL.
             body.append("--\(boundary)\r\n".data(using: .utf8)!)
             body.append("Content-Disposition: form-data; name=\"avatarUrl\"\r\n\r\n".data(using: .utf8)!)
             body.append("\r\n".data(using: .utf8)!)
        }
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isSaving = false
                
                if let error = error {
                    statusMessage = "❌ \(error.localizedDescription)"
                    return
                }
                
                guard let data = data,
                      let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    statusMessage = "❌ Server error (check logs)"
                    return
                }
                
                // Response'u parse et
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let userDict = json["user"] as? [String: Any] {
                        
                        let urlRaw = userDict["avatarUrl"] as? String ?? ""
                        var finalUrl = urlRaw
                        
                        // If no photo (SF Symbol selected), clear immediately.
                        // Backend may return old URL, so we override it.
                        if selectedImageData == nil {
                            finalUrl = ""
                        } else if !finalUrl.isEmpty {
                            let separator = finalUrl.contains("?") ? "&" : "?"
                            finalUrl = "\(finalUrl)\(separator)t=\(Date().timeIntervalSince1970)"
                        }
                        
                        // Local update
                        container.sessionStore.currentNickname = nickname
                        container.sessionStore.currentAvatarName = selectedAvatar
                        container.sessionStore.currentAvatarUrl = finalUrl // Use cache-busted URL
                        
                        // Socket broadcast
                        container.chatService.emitProfileUpdate(
                            userId: userId,
                            nickname: nickname,
                            avatarName: selectedAvatar,
                            avatarUrl: finalUrl // <-- Burda da finalUrl
                        )
                        
                        statusMessage = "✅ Profile updated!"
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            dismiss()
                        }
                    }
                } catch {
                    statusMessage = "❌ JSON Parse error"
                }
            }
        }.resume()
    }
}

#Preview {
    UserProfileView()
        .environmentObject(DependencyContainer())
}
