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
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Title
                Text("Soni App")
                    .font(.system(size:44))
                    .bold()
                    .foregroundColor(AppTheme.myBubble)
                
                Text(isLoginMode ? "Log In" : "Register")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.white)
                    .padding(.bottom, 20)
                    .padding()
                    
                
                // TextFields
                TextField("", text: $username, prompt: Text("Username")
                    .bold()
                    .foregroundColor(AppTheme.secondaryText))
                    .foregroundColor(AppTheme.white)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(AppTheme.inputBorder, lineWidth: 2)
                    )
                    .padding(.horizontal)
                    
                SecureField("", text: $password, prompt: Text("Password")
                    .bold()
                    .foregroundColor(AppTheme.secondaryText))
                    .textFieldStyle(.plain)
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(AppTheme.inputBorder, lineWidth: 2)
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
                            .background(AppTheme.primary)
                            .cornerRadius(12)
                    } else {
                        Text(isLoginMode ? "Log In" : "Register")
                            .font(.system(size: 20))
                            .bold()
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppTheme.primary)
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
                        .foregroundColor(AppTheme.secondaryText)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background.ignoresSafeArea())
        }
    }
    
    // MARK: - Actions

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

#Preview {
    AuthView()
        .environmentObject(DependencyContainer())
}
