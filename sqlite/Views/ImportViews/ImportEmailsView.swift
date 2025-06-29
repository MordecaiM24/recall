//
//  ImportEmailsView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import SwiftUI

struct EmailImportData: Codable {
    let id: String
    let thread_id: String
    let subject: String
    let sender: String
    let recipient: String
    let date: String
    let content: String
    let labels: [String]
    let snippet: String
    let readable_date: String
    let timestamp: Int64
}

struct ImportEmailsView: View {
    @EnvironmentObject var contentService: ContentService
    @State private var isImporting = false
    @State private var importedCount = 0
    @State private var showingFilePicker = false
    @State private var showingSuccess = false
    @State private var importError: String?
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            VStack(spacing: 20) {
                Image(systemName: "envelope.circle")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                VStack(spacing: 8) {
                    Text("import emails")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("select a JSON file containing your exported emails")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: 12) {
                    Text("expected format:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("""
                    [{
                      "id": "abc123",
                      "subject": "Hello",
                      "sender": "sender@example.com",
                      "recipient": "you@example.com",
                      "content": "Email content...",
                      "labels": ["INBOX"],
                      "readable_date": "2024-01-01T12:00:00Z"
                    }]
                    """)
                    .font(.caption)
                    .monospaced()
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
            
            Button(action: { showingFilePicker = true }) {
                HStack {
                    if isImporting {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Text(isImporting ? "importing..." : "select emails file")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(isImporting ? Color.gray : Color.blue)
                .cornerRadius(12)
            }
            .disabled(isImporting)
            
            Spacer()
        }
        .padding()
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result: result)
        }
        .alert("import successful!", isPresented: $showingSuccess) {
            Button("ok") { }
        } message: {
            Text("imported \(importedCount) emails successfully")
        }
        .alert("import failed", isPresented: .constant(importError != nil)) {
            Button("ok") { importError = nil }
        } message: {
            if let error = importError {
                Text(error)
            }
        }
    }
    
    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importEmails(from: url)
            
        case .failure(let error):
            importError = "failed to select file: \(error.localizedDescription)"
        }
    }
    
    private func importEmails(from url: URL) {
        isImporting = true
        importedCount = 0
        
        Task {
            do {
                guard url.startAccessingSecurityScopedResource() else {
                    throw NSError(domain: "Import", code: 1, userInfo: [NSLocalizedDescriptionKey: "no permission to access file"])
                }
                defer { url.stopAccessingSecurityScopedResource() }
                
                let data = try Data(contentsOf: url)
                let emailData = try JSONDecoder().decode([EmailImportData].self, from: data)
                
                print("got email data")
                
                let emails = emailData.map { emailInfo in
                    Email(
                        id: UUID().uuidString,
                        originalId: emailInfo.id,
                        threadId: emailInfo.thread_id,
                        subject: emailInfo.subject,
                        sender: emailInfo.sender,
                        recipient: emailInfo.recipient,
                        date: parseEmailDate(emailInfo.readable_date) ?? Date(),
                        content: emailInfo.content,
                        labels: emailInfo.labels,
                        snippet: emailInfo.snippet,
                        timestamp: emailInfo.timestamp
                    )
                }
                
                print("data shows \(emails.count) emails")
                print("attempting to import emails")
                let importedIds = try await contentService.importEmails(emails)
                
                await MainActor.run {
                    importedCount = importedIds.count
                    isImporting = false
                    showingSuccess = true
                }
                
            } catch {
                await MainActor.run {
                    isImporting = false
                    
                    importError = "failed to import emails: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func parseEmailDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString)
    }
}
