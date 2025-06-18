//
//  AddMessageView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import SwiftUI

struct AddMessageView: View {
    @EnvironmentObject var contentService: ContentService
    @State private var text = ""
    @State private var contact = ""
    @State private var chatName = ""
    @State private var chatId = ""
    @State private var service = "iMessage"
    @State private var isFromMe = true
    @State private var isLoading = false
    @State private var showingSuccess = false
    
    let services = ["iMessage", "SMS", "WhatsApp", "Telegram"]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("message text")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("enter message text...", text: $text, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...8)
                }
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("contact")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        TextField("contact name", text: $contact)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("chat name")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        TextField("chat name", text: $chatName)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("chat id / phone number")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("+1234567890", text: $chatId)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.phonePad)
                }
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("service")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Picker("service", selection: $service) {
                            ForEach(services, id: \.self) { service in
                                Text(service).tag(service)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("from me")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Toggle("", isOn: $isFromMe)
                            .labelsHidden()
                    }
                }
                
                Button(action: addMessage) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(isLoading ? "adding..." : "add message")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canAdd ? Color.blue : Color.gray)
                    .cornerRadius(12)
                }
                .disabled(!canAdd || isLoading)
                
                Spacer(minLength: 50)
            }
            .padding()
        }
        .alert("message added!", isPresented: $showingSuccess) {
            Button("ok") {
                clearForm()
            }
        }
    }
    
    private var canAdd: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !chatId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func addMessage() {
        isLoading = true
        
        Task {
            do {
                let message = Message(
                    id: UUID().uuidString,
                    originalId: Int32.random(in: 1...999999),
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    date: Date(),
                    timestamp: Int64(Date().timeIntervalSince1970 * 1_000_000_000),
                    isFromMe: isFromMe,
                    isSent: true,
                    service: service,
                    contact: contact.isEmpty ? nil : contact.trimmingCharacters(in: .whitespacesAndNewlines),
                    chatName: chatName.trimmingCharacters(in: .whitespacesAndNewlines),
                    chatId: chatId.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                
                _ = try await contentService.addMessage(message)
                
                await MainActor.run {
                    isLoading = false
                    showingSuccess = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
    
    private func clearForm() {
        text = ""
        contact = ""
        chatName = ""
        chatId = ""
        service = "iMessage"
        isFromMe = true
    }
}
