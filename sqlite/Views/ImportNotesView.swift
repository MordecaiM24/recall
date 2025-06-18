//
//  ImportNotesView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import SwiftUI

struct NoteImportData: Codable {
    let id: Int
    let title: String
    let snippet: String?
    let content: String
    let folder: String
    let created: String?
    let modified: String
    let creation_timestamp: Double?
    let modification_timestamp: Double
}

struct ImportNotesView: View {
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
                Image(systemName: "note.text")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                VStack(spacing: 8) {
                    Text("import notes")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("select a JSON file containing your exported notes")
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
                      "id": 123,
                      "title": "My Note",
                      "content": "Note content...",
                      "folder": "Notes",
                      "modified": "2024-01-01 12:00:00",
                      "modification_timestamp": 123456789
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
                    Text(isImporting ? "importing..." : "select notes file")
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
            Text("imported \(importedCount) notes successfully")
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
            importNotes(from: url)
            
        case .failure(let error):
            importError = "failed to select file: \(error.localizedDescription)"
        }
    }
    
    private func importNotes(from url: URL) {
        isImporting = true
        importedCount = 0
        
        Task {
            do {
                guard url.startAccessingSecurityScopedResource() else {
                    throw NSError(domain: "Import", code: 1, userInfo: [NSLocalizedDescriptionKey: "no permission to access file"])
                }
                defer { url.stopAccessingSecurityScopedResource() }
                
                let data = try Data(contentsOf: url)
                let noteData = try JSONDecoder().decode([NoteImportData].self, from: data)
                
                var successCount = 0
                var errorCount = 0
                
                for noteInfo in noteData {
                    do {
                        let note = Note(
                            id: UUID().uuidString,
                            originalId: Int32(noteInfo.id),
                            title: noteInfo.title,
                            snippet: noteInfo.snippet,
                            content: noteInfo.content,
                            folder: noteInfo.folder,
                            created: noteInfo.created.flatMap { parseNoteDate($0) },
                            modified: parseNoteDate(noteInfo.modified) ?? Date(),
                            creationTimestamp: noteInfo.creation_timestamp,
                            modificationTimestamp: noteInfo.modification_timestamp
                        )
                        
                        // attempt to add note - this includes both db insert and embedding
                        _ = try await contentService.addNote(note)
                        successCount += 1
                        
                    } catch {
                        print("failed to import note \(noteInfo.id): \(error)")
                        errorCount += 1
                        // continue with next note instead of stopping
                    }
                }
                
                await MainActor.run {
                    importedCount = successCount
                    isImporting = false
                    if successCount > 0 {
                        showingSuccess = true
                        if errorCount > 0 {
                            print("import completed with \(successCount) successes and \(errorCount) errors")
                        }
                    } else {
                        importError = "no notes were imported successfully (\(errorCount) failed)"
                    }
                }
                
            } catch {
                await MainActor.run {
                    isImporting = false
                    importError = "failed to import notes: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func parseNoteDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: dateString)
    }
}
