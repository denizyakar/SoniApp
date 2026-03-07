//
//  AuthView.swift
//  SoniApp

import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var container: DependencyContainer
    
    // Local state
    @State private var isLoginMode = true
    @State private var username = ""
    @State private var password = ""
    @State private var message = ""
    @State private var isSuccess = false
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                
                Spacer()
                
                // Title
                Text("Soni App")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundColor(AppTheme.myBubble)
                
                Text(isLoginMode ? "Log In" : "Register")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.white)
                    .padding(.bottom, 12)
                
                // TextFields
                TextField("", text: $username, prompt: Text("Username")
                    .bold()
                    .foregroundColor(AppTheme.secondaryText))
                    .foregroundColor(AppTheme.white)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.next)
                    .padding(14)
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.inputBorder, lineWidth: 1.5)
                    )
                    .padding(.horizontal, 24)
                    
                SecureField("", text: $password, prompt: Text("Password")
                    .bold()
                    .foregroundColor(AppTheme.secondaryText))
                    .foregroundColor(AppTheme.white)
                    .textFieldStyle(.plain)
                    .submitLabel(.go)
                    .onSubmit { handleAction() }
                    .padding(14)
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.inputBorder, lineWidth: 1.5)
                    )
                    .padding(.horizontal, 24)
                
                // Status message
                if !message.isEmpty {
                    Text(message)
                        .foregroundColor(isSuccess ? .green : .red)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                
                // Button
                Button(action: handleAction) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppTheme.primary)
                            .cornerRadius(14)
                    } else {
                        Text(isLoginMode ? "Log In" : "Register")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppTheme.primary)
                            .cornerRadius(14)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .disabled(isLoading)
                
                // Changing modes
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isLoginMode.toggle()
                        message = ""
                        isSuccess = false
                    }
                }) {
                    Text(isLoginMode ? "Don't have an account? Register" : "Already have an account? Log In")
                        .padding(.top, 4)
                        .foregroundColor(AppTheme.secondaryText)
                        .font(.subheadline)
                        .bold()
                }
                
                Spacer()
                Spacer()
                
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background.ignoresSafeArea())
        }
    }
    
    // MARK: - Actions

    private func handleAction() {
        isLoading = true
        isSuccess = false
        let authService = container.makeAuthService()
        
        if isLoginMode {
            authService.login(username: username, password: password) { [self] result in
                DispatchQueue.main.async {
                    isLoading = false
                    switch result {
                    case .success:
                        print("Login successful!")
                    case .failure(let error):
                        isSuccess = false
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
                        isSuccess = true
                        message = msg
                        isLoginMode = true
                        username = ""
                        password = ""
                    case .failure(let error):
                        isSuccess = false
                        message = error.localizedDescription
                    }
                }
            }
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(DependencyContainer())
}
