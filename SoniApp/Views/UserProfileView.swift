//
//  UserProfileView.swift
//  SoniApp
//
//  Kullanıcı profil ekranı: avatar seçimi (galeri + SF Symbol) ve nickname değiştirme.
//

import SwiftUI
import SwiftUI
// import PhotosUI - Artık gerek yok

struct UserProfileView: View {
    @EnvironmentObject private var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss
    
    @State private var nickname: String = ""
    @State private var selectedAvatar: String = "person.circle"
    
    // YENİ: Fotoğraf seçimi için state'ler (ImagePicker için)
    @State private var showImagePicker = false
    @State private var inputImage: UIImage?
    @State private var selectedImageData: Data?
    @State private var avatarUrl: String = "" // Server'dan gelen URL string
    
    @State private var isSaving = false
    @State private var statusMessage = ""
    
    /// Kullanılabilir avatar seçenekleri (SF Symbols)
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
                Section("Avatar") {
                    VStack {
                        // Büyük önizleme
                        if let data = selectedImageData, let uiImage = UIImage(data: data) {
                            // Galeriden yeni seçilen (henüz upload edilmemiş)
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                        } else if !avatarUrl.isEmpty {
                            // Server'daki mevcut fotoğraf
                            AsyncImage(url: URL(string: "\(APIEndpoints.baseURL)\(avatarUrl)")) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                        } else {
                            // SF Symbol
                            Image(systemName: selectedAvatar)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 100, height: 100)
                                .foregroundColor(.blue)
                        }
                        
                        // Fotoğraf Seç Butonu (Kırpma Özellikli)
                        Button {
                            showImagePicker = true
                        } label: {
                            Label("Select Photo", systemImage: "photo.on.rectangle")
                                .font(.headline)
                                .padding(.vertical, 4)
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
                            // ImagePicker zaten kırpılmış (edited) kare fotoğrafı döndürüyor.
                            // Yine de boyutunu standardize etmek (256x256) ve sıkıştırmak iyi olur.
                            if let data = newImage.jpegData(compressionQuality: 0.8) {
                                // Resize işlemi processImage içinde yapılıyor, oraya gönderelim
                                // processImage Data alıyor, o yüzden önce data yaptık.
                                // Aslında processImage UIImage alsa daha verimli olurdu ama mevcut yapıyı bozmayalım.
                                if let compressed = processImage(data: data) {
                                    selectedImageData = compressed
                                }
                            }
                        }
                    }
                    
                    // SF Symbol Grid (Sadece fotoğraf seçilmediyse veya iptal edilmek istenirse?)
                    // Hem fotoğraf hem symbol seçilebilir, fotoğraf varsa fotoğraf önceliklidir.
                    // Fotoğrafı iptal etmek için bir buton ekleyebiliriz veya symbol seçince fotoğrafı silebiliriz.
                    
                    if selectedImageData != nil || !avatarUrl.isEmpty {
                        Button(role: .destructive) {
                            selectedImageData = nil
                            avatarUrl = ""
                            // Varsayılana dön
                            selectedAvatar = "person.circle"
                        } label: {
                            Label("Remove Photo", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    
                    // Avatar grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(avatarOptions, id: \.self) { avatar in
                            Image(systemName: avatar)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 32, height: 32)
                                .foregroundColor(selectedAvatar == avatar ? .blue : .gray)
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedAvatar == avatar ? Color.blue.opacity(0.15) : Color.clear)
                                )
                                .onTapGesture {
                                    selectedAvatar = avatar
                                    // Symbol seçince fotoğrafı temizle
                                    selectedImageData = nil
                                    avatarUrl = ""
                                }
                        }
                    }
                    .padding(.top, 8)
                }
                
                // MARK: - Nickname
                Section("Nickname") {
                    TextField("Enter nickname", text: $nickname)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    Text("This will be displayed instead of your username.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // MARK: - Bilgi
                Section {
                    HStack {
                        Text("Username")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(container.sessionStore.currentUsername ?? "—")
                    }
                }
                
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
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                // Mevcut değerleri yükle
                nickname = container.sessionStore.currentNickname ?? ""
                selectedAvatar = container.sessionStore.currentAvatarName ?? "person.circle"
                avatarUrl = container.sessionStore.currentAvatarUrl ?? ""
            }
        }
    }
    
    // MARK: - Helpers
    
    /// Fotoğrafı resize ve compress et (~30-80KB hedefleniyor)
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
        
        // Multipart request oluştur
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
        // Eğer fotoğraf varsa avatarName'i de gönderiyoruz ama öncelik url'de olacak
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
             // Fotoğraf yoksa (SF Symbol kullanılıyorsa) URL'i temizlemek için boş string gönde.
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
                        
                        // YENİ: Eğer fotoğraf yoksa (SF Symbol seçildiyse) anında temizle.
                        // Backend bazen eski URL'i dönebiliyor olabilir, onu override edelim.
                        if selectedImageData == nil {
                            finalUrl = ""
                        } else if !finalUrl.isEmpty {
                            let separator = finalUrl.contains("?") ? "&" : "?"
                            finalUrl = "\(finalUrl)\(separator)t=\(Date().timeIntervalSince1970)"
                        }
                        
                        // Lokal güncelleme
                        container.sessionStore.currentNickname = nickname
                        container.sessionStore.currentAvatarName = selectedAvatar
                        container.sessionStore.currentAvatarUrl = finalUrl // <-- Cache-buster'lı URL kullan!
                        
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
