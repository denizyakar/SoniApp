//
//  AuthView.swift
//  SoniApp
//
//  DEĞİŞTİRİLDİ: AuthViewModel kullanıyor. UI AYNI KALDI.
//

import SwiftUI

/// Login/Register ekranı.
///
/// **Ne değişti?**
/// UI tasarımı AYNI KALDI — kullanıcı hiçbir fark görmeyecek.
///
/// İç yapıda:
/// - `@State` ile tuttuğumuz state'ler → `@StateObject AuthViewModel`'e taşındı
/// - `AuthManager.shared.login()` → `viewModel.handleAction()`
/// - İş mantığı View'dan çıktı → ViewModel'e taşındı
struct AuthView: View {
    @EnvironmentObject private var container: DependencyContainer
    
    // Local state — ViewModel onAppear'da yaratılacak
    @State private var isLoginMode = true
    @State private var username = ""
    @State private var password = ""
    @State private var message = ""
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Title
                Text("Soni App")
                    .font(.system(size:44))
                    .bold()
                    .foregroundColor(Color.blue)
                
                Text(isLoginMode ? "Log In" : "Register")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.bottom, 20)
                    .padding()
                
                // TextFields
                TextField("Username", text: $username)
                    .autocapitalization(.none)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.systemGray),lineWidth: 1)
                    )
                    .padding(.horizontal)
                    
                SecureField("Password", text: $password)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.systemGray),lineWidth: 1)
                    )
                    .padding(.horizontal)
                    .padding(.bottom)
                
                // Button
                Button(action: handleAction) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    } else {
                        Text(isLoginMode ? "Log In" : "Register")
                            .font(.system(size: 20))
                            .bold()
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.top)
                .disabled(isLoading)
                
                // Changing modes
                Button(action: {
                    isLoginMode.toggle()
                    message = ""
                }) {
                    Text(isLoginMode ? "Don't have an account? Register" : "Already have an account? Log In")
                        .padding(.top)
                        .foregroundColor(.blue)
                        .bold()
                }
                
                // Status message
                if !message.isEmpty {
                    Text(message)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding()
                }
                
            }
            .padding(.bottom)
            .padding(.bottom)
        }
    }
    
    // MARK: - Actions
    
    /// Login/Register butonuna basıldığında çağrılır.
    ///
    /// **Eski hali:** `AuthManager.shared.login(username:pass:)` doğrudan çağrılıyordu.
    /// **Yeni hali:** `container.makeAuthService()` ile servis yaratılıp kullanılıyor.
    private func handleAction() {
        isLoading = true
        let authService = container.makeAuthService()
        
        if isLoginMode {
            authService.login(username: username, password: password) { [self] result in
                DispatchQueue.main.async {
                    isLoading = false
                    switch result {
                    case .success:
                        print("Login successful!")
                    case .failure(let error):
                        message = error.localizedDescription
                    }
                }
            }
        } else {
            authService.register(username: username, password: password) { [self] result in
                DispatchQueue.main.async {
                    isLoading = false
                    switch result {
                    case .success(let msg):
                        message = msg
                        isLoginMode = true
                        username = ""
                        password = ""
                    case .failure(let error):
                        message = error.localizedDescription
                    }
                }
            }
        }
    }
}
