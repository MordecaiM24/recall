//
//  ContentView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 5/25/25.
//
import SwiftUI

struct ContentView: View {
    @StateObject private var documentService = try! DocumentService()
     
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            DocumentView()
                .environmentObject(documentService)
                .tabItem {
                    Image(systemName: "doc.text")
                    Text("Documents")
                }
                .tag(0)
            
            SearchView()
                .environmentObject(documentService)
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("Search")
                }
                .tag(1)
        }
    }
}

struct DocumentView: View {
    @EnvironmentObject var documentService: DocumentService
    @State private var title = ""
    @State private var content = ""
    @State private var showingAddDocument = false
    
    var body: some View {
        NavigationView {
            VStack {
                if documentService.isLoading {
                    ProgressView("Processing...")
                        .padding()
                }
                
                if let error = documentService.error {
                    ErrorView(error: error) {
                        documentService.clearError()
                    }
                }
                
                List(documentService.documents) { document in
                    DocumentRowView(document: document)
                }
                .refreshable {
                    documentService.refresh()
                }
            }
            .navigationTitle("Knowledge Base")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add") {
                        showingAddDocument = true
                    } 
                }
            }
            .sheet(isPresented: $showingAddDocument) {
                AddDocumentView(
                    title: $title,
                    content: $content,
                    onSave: {
                        Task {
                            await documentService.addDocument(title: title, content: content)
                            title = ""
                            content = ""
                            showingAddDocument = false
                        }
                    },
                    onCancel: {
                        showingAddDocument = false
                    }
                )
            }
        }
    }
}

struct SearchView: View {
    @EnvironmentObject var documentService: DocumentService
    @State private var searchQuery = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching = false
    
    var body: some View {
        NavigationView {
            VStack {
                SearchBar(text: $searchQuery, onSearchButtonClicked: performSearch)
                
                if isSearching {
                    ProgressView("Searching...")
                        .padding()
                }
                
                List(searchResults) { result in
                    SearchResultRowView(result: result)
                }
            }
            .navigationTitle("Search")
        }
    }
    
    private func performSearch() {
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        isSearching = true
        Task {
            let results = await documentService.search(query: searchQuery)
            await MainActor.run {
                searchResults = results
                isSearching = false
            }
        }
    }
    
    
}

// MARK: - Supporting Views

struct DocumentRowView: View {
    let document: Document
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(document.title)
                .font(.headline)
            Text(document.preview)
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(3)
            Text(document.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundColor(.accentColor)
        }
        .padding(.vertical, 2)
    }
}

struct SearchResultRowView: View {
    let result: SearchResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(result.document.title)
                    .font(.headline)
                Spacer()
                Text(result.similarityPercentage)
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            Text(result.document.preview)
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(3)
        }
        .padding(.vertical, 2)
    }
}

struct AddDocumentView: View {
    @Binding var title: String
    @Binding var content: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                
                TextEditor(text: $content)
                    .border(Color.gray.opacity(0.3))
                
                Spacer()
            }
            .padding()
            .navigationTitle("Add Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .disabled(title.isEmpty || content.isEmpty)
                }
            }
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    let onSearchButtonClicked: () -> Void
    
    var body: some View {
        HStack {
            TextField("Search your knowledge base...", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    onSearchButtonClicked()
                }
            
            Button("Search", action: onSearchButtonClicked)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
    }
}

struct ErrorView: View {
    let error: Error
    let onDismiss: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.red)
            Text(error.localizedDescription)
                .font(.caption)
            Spacer()
            Button("Dismiss", action: onDismiss)
                .font(.caption)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

#Preview {
    ContentView()
}
