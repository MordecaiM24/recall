//
//  AddEmailView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import SwiftUI

struct AddEmailView: View {
    @EnvironmentObject var contentService: ContentService
    @State private var subject = ""
    @State private var sender = ""
    @State private var recipient = ""
    @State private var content = ""
    @State private var selectedLabels: Set<String> = ["INBOX"]
    @State private var isLoading = false
    @State private var showingSuccess = false
    
    let availableLabels = ["INBOX", "SENT", "DRAFT", "CATEGORY_PROMOTIONS", "CATEGORY_SOCIAL", "IMPORTANT", "STARRED"]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("subject")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("email subject...", text: $subject)
                        .textFieldStyle(.roundedBorder)
                }
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("sender")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        TextField("sender@example.com", text: $sender)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.emailAddress)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("recipient")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        TextField("you@example.com", text: $recipient)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.emailAddress)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("content")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("email content...", text: $content, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(8...15)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("labels")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                        ForEach(availableLabels, id: \.self) { label in
                            Button(action: {
                                if selectedLabels.contains(label) {
                                    selectedLabels.remove(label)
                                } else {
                                    selectedLabels.insert(label)
                                }
                            }) {
                                Text(label)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedLabels.contains(label) ? Color.blue : Color(.systemGray5))
                                    .foregroundColor(selectedLabels.contains(label) ? .white : .primary)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Button(action: addEmail) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(isLoading ? "adding..." : "add email")
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
        .alert("email added!", isPresented: $showingSuccess) {
            Button("ok") {
                clearForm()
            }
        }
    }
    
    private var canAdd: Bool {
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !sender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func addEmail() {
        isLoading = true
        
        Task {
            do {
                let email = Email(
                    id: UUID().uuidString,
                    originalId: UUID().uuidString,
                    threadId: UUID().uuidString,
                    subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
                    sender: sender.trimmingCharacters(in: .whitespacesAndNewlines),
                    recipient: recipient.trimmingCharacters(in: .whitespacesAndNewlines),
                    date: Date(),
                    content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                    labels: Array(selectedLabels),
                    snippet: String(content.prefix(100)),
                    timestamp: Int64(Date().timeIntervalSince1970)
                )
                
                _ = try await contentService.addEmail(email)
                
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
        subject = ""
        sender = ""
        recipient = ""
        content = ""
        selectedLabels = ["INBOX"]
    }
}
