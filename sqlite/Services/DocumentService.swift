//
//  DocumentService.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 5/27/25.
//
import Foundation
import Combine

enum DocumentServiceError: Error {
    case embeddingFailed(Error)
    case storageFailed(Error)
    case searchFailed(Error)
    case serviceUnavailable
}

@MainActor
final class DocumentService: ObservableObject {
    @Published private(set) var documents: [Document] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    private let sqliteService: SQLiteService
    private let embeddingService: EmbeddingService
    
    init() throws {
        self.embeddingService = try EmbeddingService()
        self.sqliteService = try SQLiteService(embeddingDimensions: embeddingService.embeddingDimensions)
        
        // setup database
        try sqliteService.setupDatabase()
        
        // load initial documents
        refresh()
    }
    
    
    
    // MARK: - Document Management
    
    func addDocument(title: String, content: String) async {
        isLoading = true
        error = nil
        
        do {
            // generate embedding
            let text = "\(title)\n\n\(content)"
            let embedding = try await embeddingService.embed(text: text)
            
            // store document with embedding
            let documentId = try sqliteService.insertDocument(
                title: title,
                content: content,
                embedding: embedding
            )
            
            // refresh document list
            refresh()
            
        } catch {
            self.error = DocumentServiceError.embeddingFailed(error)
        }
        
        isLoading = false
    }
    
    func refresh() {
        Task {
            do {
                let docs = try sqliteService.findAllDocuments()
                await MainActor.run {
                    documents = docs
                }
            } catch {
                await MainActor.run {
                    self.error = DocumentServiceError.storageFailed(error)
                }
            }
        }
    }
    
    // MARK: - Search
    
    func search(query: String, limit: Int = 10) async -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        
        do {
            let queryEmbedding = try await embeddingService.embed(text: query)
            
            let results = try sqliteService.searchDocuments(
                queryEmbedding: queryEmbedding,
                limit: limit
            )
            
            return results
        } catch {
            await MainActor.run {
                self.error = DocumentServiceError.searchFailed(error)
            }
            return []
        }
        
        
    }
    
    // MARK: - Batch Operations
    
    func addDocuments(_ documents: [(title: String, content: String)]) async {
        isLoading = true
        error = nil
        
        do {
            // batch embed all documents
            let texts = documents.map { "\($0.title)\n\n\($0.content)" }
            let embeddings = try await embeddingService.embed(texts: texts)
            
            // store all documents
            for (i, doc) in documents.enumerated() {
                _ = try sqliteService.insertDocument(
                    title: doc.title,
                    content: doc.content,
                    embedding: embeddings[i]
                )
            }
            
            refresh()
            
        } catch {
            self.error = DocumentServiceError.embeddingFailed(error)
        }
        
        isLoading = false
    }
    
    // MARK: - Document Retrieval
    
    func getDocument(id: String) -> Document? {
        return documents.first { $0.id == id }
    }
    
    func getDocuments(containing text: String) -> [Document] {
        let searchText = text.lowercased()
        return documents.filter { doc in
            doc.title.lowercased().contains(searchText) ||
            doc.content.lowercased().contains(searchText)
        }
    }
    
    // MARK: - Error Handling
    
    func clearError() {
        error = nil
    }
}
