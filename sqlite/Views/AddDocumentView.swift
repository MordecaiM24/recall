//
//  AddDocumentView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import SwiftUI

struct AddDocumentView: View {
    @EnvironmentObject var contentService: ContentService
    @State private var title = ""
    @State private var content = ""
    @State private var isLoading = false
    @State private var showingSuccess = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("document title")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("enter document title...", text: $title)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("content")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("enter document content...", text: $content, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(10...20)
                }
                
                Button(action: addDocument) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(isLoading ? "adding..." : "add document")
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
        .alert("document added!", isPresented: $showingSuccess) {
            Button("ok") {
                clearForm()
            }
        }
    }
    
    private var canAdd: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func addDocument() {
        isLoading = true
        
        Task {
            do {
                _ = try await contentService.addDocument(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    content: content.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                
                await MainActor.run {
                    isLoading = false
                    showingSuccess = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    // could show error alert here
                }
            }
        }
    }
    
    private func clearForm() {
        title = ""
        content = ""
    }
}
