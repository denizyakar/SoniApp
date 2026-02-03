//
//  AuthView.swift
//  SoniApp
//
//  Created by Ali Deniz Yakar on 26.01.2026.
//

import SwiftUI

struct AuthView: View {
    @State private var isLoginMode = true
    @State private var username = ""
    @State private var password = ""
    @State private var message = ""
    @State private var showAlert = false
    
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
                    Text(isLoginMode ? "Log In" : "Register")
                        .font(.system(size: 20))
                        .bold()
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.top)
                
                // Changing mods
                Button(action: {
                    isLoginMode.toggle()
                    message = ""
                }) {
                    Text(isLoginMode ? "Don't have an account? Register" : "Already have an account? Log In")
                        .padding(.top)
                        .foregroundColor(.blue)
                        .bold()
                }
                
                // Situation
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
    
    // What will happen after pressing the button?
    private func handleAction() {
        if isLoginMode {
            // Logging in.
            AuthManager.shared.login(username: username, pass: password) { success, errorMsg in
                DispatchQueue.main.async {
                    if success {
                        // If successful, view will change
                        print("Login succesful!")
                    } else {
                        self.message = errorMsg ?? "Error"
                    }
                }
            }
        } else {
            // Registering.
            AuthManager.shared.register(username: username, pass: password) { success, errorMsg in
                DispatchQueue.main.async {
                    if success {
                        self.message = "Registering succesful, you can now log in."
                        self.isLoginMode = true // Back to login view
                        self.username = ""
                        self.password = ""
                    } else {
                        self.message = errorMsg ?? "Error"
                    }
                }
            }
        }
    }
}

#Preview {
    AuthView()
}
