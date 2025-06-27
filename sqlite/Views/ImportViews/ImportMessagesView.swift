//
//  ImportMessagesView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import SwiftUI

struct MessageImportData: Codable {
    let id: Int
    let text: String
    let date: String
    let timestamp: Int64
    let is_from_me: Bool
    let is_sent: Bool
    let service: String
    let contact: String
    let chat_name: String?
    let chat_id: String?
    let contact_number: String?
}

struct ImportMessagesView: View {
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
                Image(systemName: "message.circle")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                VStack(spacing: 8) {
                    Text("import messages")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("select a JSON file containing your exported messages")
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
                      "id": 12345,
                      "text": "hello world",
                      "date": "2024-01-01 12:00:00",
                      "timestamp": 123456789,
                      "is_from_me": true,
                      "is_sent": true,
                      "service": "iMessage",
                      "contact": "John",
                      "chat_name": "John",
                      "chat_id": "+1234567890"
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
                    Text(isImporting ? "importing..." : "select messages file")
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
            Text("imported \(importedCount) messages successfully")
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
            importMessages(from: url)
            
        case .failure(let error):
            importError = "failed to select file: \(error.localizedDescription)"
        }
    }
    
    private func importMessages(from url: URL) {
        isImporting = true
        importedCount = 0
        
        Task {
            do {
                guard url.startAccessingSecurityScopedResource() else {
                    throw NSError(domain: "Import", code: 1, userInfo: [NSLocalizedDescriptionKey: "no permission to access file"])
                }
                defer { url.stopAccessingSecurityScopedResource() }
                
                let data = try Data(contentsOf: url)
                let messageData = try JSONDecoder().decode([MessageImportData].self, from: data).sorted(by: { $0.date < $1.date }).suffix(500)
                
                let messages = messageData.map { msgData in
                    Message(
                        id: UUID().uuidString,
                        originalId: Int32(msgData.id),
                        text: msgData.text,
                        date: parseDate(msgData.date) ?? Date(),
                        timestamp: msgData.timestamp,
                        isFromMe: msgData.is_from_me,
                        isSent: msgData.is_sent,
                        service: msgData.service,
                        contact: msgData.contact,
                        chatName: msgData.chat_name,
                        chatId: msgData.chat_id,
                        contactNumber: msgData.contact_number
                    )
                }
                
                let importedIds = try await contentService.importMessages(messages)
                
                await MainActor.run {
                    importedCount = importedIds.count
                    isImporting = false
                    showingSuccess = true
                }
                
            } catch {
                await MainActor.run {
                    isImporting = false
                    importError = "failed to import messages: \(error.localizedDescription)"
                    print(error)
                }
            }
        }
    }
    
    private func parseDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: dateString)
    }
}
