//
//  AddNoteView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import SwiftUI

struct AddNoteView: View {
    @EnvironmentObject var contentService: ContentService
    @State private var title = ""
    @State private var content = ""
    @State private var folder = "Notes"
    @State private var isLoading = false
    @State private var showingSuccess = false
    
    let availableFolders = ["Notes", "Personal", "Work", "Ideas", "Research", "Shopping", "Travel"]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("note title")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("note title...", text: $title)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("folder")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Picker("folder", selection: $folder) {
                        ForEach(availableFolders, id: \.self) { folder in
                            Text(folder).tag(folder)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 100)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("content")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("note content...", text: $content, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(10...20)
                }
                
                Button(action: addNote) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(isLoading ? "adding..." : "add note")
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
        .alert("note added!", isPresented: $showingSuccess) {
            Button("ok") {
                clearForm()
            }
        }
    }
    
    private var canAdd: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func addNote() {
        isLoading = true
        
        Task {
            do {
                let note = Note(
                    id: UUID().uuidString,
                    originalId: Int32.random(in: 1...999999),
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    snippet: String(content.prefix(100)),
                    content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                    folder: folder,
                    created: Date(),
                    modified: Date(),
                    creationTimestamp: Date().timeIntervalSinceReferenceDate,
                    modificationTimestamp: Date().timeIntervalSinceReferenceDate
                )
                
                _ = try await contentService.addNote(note)
                
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
        title = ""
        content = ""
        folder = "Notes"
    }
}

