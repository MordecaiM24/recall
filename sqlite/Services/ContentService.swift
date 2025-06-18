//
//  ContentService.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import Foundation
import Combine

enum ContentServiceError: Error {
    case embeddingFailed(Error)
    case storageFailed(Error)
    case searchFailed(Error)
    case serviceUnavailable
    case invalidContentType
}

@MainActor
final class ContentService: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    private let sqliteService: SQLiteService
    private let embeddingService: EmbeddingService
    
    init() throws {
        self.embeddingService = try EmbeddingService()
        self.sqliteService = try SQLiteService(embeddingDimensions: embeddingService.embeddingDimensions)
        
        try sqliteService.setupDatabase()
    }
    
    // dependency injection initializer for testing
    init(sqliteService: SQLiteService, embeddingService: EmbeddingService) throws {
        self.sqliteService = sqliteService
        self.embeddingService = embeddingService
    }
    
    // MARK: - Document Operations
    
    func addDocument(title: String, content: String) async throws -> String {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let document = Document(
                id: UUID().uuidString,
                title: title,
                content: content
            )
            
            let embedding = try await embeddingService.embed(text: document.embeddableText)
            let documentId = try sqliteService.insertDocument(
                title: document.title,
                content: document.content,
                embedding: embedding
            )
            
            return documentId
        } catch {
            self.error = ContentServiceError.embeddingFailed(error)
            throw error
        }
    }
    
    func getAllDocuments() async throws -> [Document] {
        do {
            return try sqliteService.findAllDocuments()
        } catch {
            self.error = ContentServiceError.storageFailed(error)
            throw error
        }
    }
    
    // MARK: - Message Operations
    
    func addMessage(_ message: Message) async throws -> String {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let messageId = try sqliteService.insertMessage(message.toData)
            let embedding = try await embeddingService.embed(text: message.embeddableText)
            
            try sqliteService.insertChunk(
                parentId: messageId,
                contentType: .message,
                chunkIndex: 0,
                text: message.embeddableText,
                embedding: embedding
            )
            
            return messageId
        } catch {
            self.error = ContentServiceError.storageFailed(error)
            throw error
        }
    }
    
    func getMessage(id: String) async throws -> Message? {
        do {
            guard let data = try sqliteService.findMessage(id: id) else {
                return nil
            }
            return Message(from: data)
        } catch {
            self.error = ContentServiceError.storageFailed(error)
            throw error
        }
    }
    
    // MARK: - Email Operations
    
    func addEmail(_ email: Email) async throws -> String {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let emailId = try sqliteService.insertEmail(email.toData)
            let embedding = try await embeddingService.embed(text: email.embeddableText)
            
            try sqliteService.insertChunk(
                parentId: emailId,
                contentType: .email,
                chunkIndex: 0,
                text: email.embeddableText,
                embedding: embedding
            )
            
            return emailId
        } catch {
            self.error = ContentServiceError.storageFailed(error)
            throw error
        }
    }
    
    func getEmail(id: String) async throws -> Email? {
        do {
            guard let data = try sqliteService.findEmail(id: id) else {
                return nil
            }
            return Email(from: data)
        } catch {
            self.error = ContentServiceError.storageFailed(error)
            throw error
        }
    }
    
    // MARK: - Note Operations
    
    func addNote(_ note: Note) async throws -> String {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let noteId = try sqliteService.insertNote(note.toData)
            let embedding = try await embeddingService.embed(text: note.embeddableText)
            
            try sqliteService.insertChunk(
                parentId: noteId,
                contentType: .note,
                chunkIndex: 0,
                text: note.embeddableText,
                embedding: embedding
            )
            
            return noteId
        } catch {
            self.error = ContentServiceError.storageFailed(error)
            throw error
        }
    }
    
    func getNote(id: String) async throws -> Note? {
        do {
            guard let data = try sqliteService.findNote(id: id) else {
                return nil
            }
            return Note(from: data)
        } catch {
            self.error = ContentServiceError.storageFailed(error)
            throw error
        }
    }
    
    // MARK: - Unified Search
    
    func search(query: String, limit: Int = 20, contentTypes: [ContentType] = ContentType.allCases) async -> [UnifiedContent] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }
        
        do {
            let queryEmbedding = try await embeddingService.embed(text: trimmedQuery)
            
            let results = try sqliteService.searchAllContent(
                queryEmbedding: queryEmbedding,
                limit: limit,
                contentTypes: contentTypes
            )
            
            var unifiedResults: [UnifiedContent] = []
            
            for result in results {
                switch result.type {
                case .document:
                    if let doc = try? sqliteService.findDocument(id: result.id) {
                        unifiedResults.append(UnifiedContent(from: doc, distance: result.distance))
                    }
                case .message:
                    if let data = try? sqliteService.findMessage(id: result.id) {
                        let message = Message(from: data)
                        unifiedResults.append(UnifiedContent(from: message, distance: result.distance))
                    }
                case .email:
                    if let data = try? sqliteService.findEmail(id: result.id) {
                        let email = Email(from: data)
                        unifiedResults.append(UnifiedContent(from: email, distance: result.distance))
                    }
                case .note:
                    if let data = try? sqliteService.findNote(id: result.id) {
                        let note = Note(from: data)
                        unifiedResults.append(UnifiedContent(from: note, distance: result.distance))
                    }
                }
            }
            
            return unifiedResults
            
        } catch {
            await MainActor.run {
                self.error = ContentServiceError.searchFailed(error)
            }
            return []
        }
    }
    
    // MARK: - Batch Operations
    
    func addMessages(_ messages: [Message]) async throws -> [String] {
        isLoading = true
        defer { isLoading = false }
        
        var messageIds: [String] = []
        
        do {
            for message in messages {
                let messageId = try sqliteService.insertMessage(message.toData)
                let embedding = try await embeddingService.embed(text: message.embeddableText)
                
                try sqliteService.insertChunk(
                    parentId: messageId,
                    contentType: .message,
                    chunkIndex: 0,
                    text: message.embeddableText,
                    embedding: embedding
                )
                
                messageIds.append(messageId)
            }
            
            return messageIds
        } catch {
            self.error = ContentServiceError.storageFailed(error)
            throw error
        }
    }
    
    func addEmails(_ emails: [Email]) async throws -> [String] {
        isLoading = true
        defer { isLoading = false }
        
        var emailIds: [String] = []
        
        do {
            for email in emails {
                let emailId = try sqliteService.insertEmail(email.toData)
                let embedding = try await embeddingService.embed(text: email.embeddableText)
                
                try sqliteService.insertChunk(
                    parentId: emailId,
                    contentType: .email,
                    chunkIndex: 0,
                    text: email.embeddableText,
                    embedding: embedding
                )
                
                emailIds.append(emailId)
            }
            
            return emailIds
        } catch {
            self.error = ContentServiceError.storageFailed(error)
            throw error
        }
    }
    
    func addNotes(_ notes: [Note]) async throws -> [String] {
        isLoading = true
        defer { isLoading = false }
        
        var noteIds: [String] = []
        
        do {
            for note in notes {
                let noteId = try sqliteService.insertNote(note.toData)
                let embedding = try await embeddingService.embed(text: note.embeddableText)
                
                try sqliteService.insertChunk(
                    parentId: noteId,
                    contentType: .note,
                    chunkIndex: 0,
                    text: note.embeddableText,
                    embedding: embedding
                )
                
                noteIds.append(noteId)
            }
            
            return noteIds
        } catch {
            self.error = ContentServiceError.storageFailed(error)
            throw error
        }
    }
    
    // MARK: - Search by Content Type
    
    func searchDocuments(query: String, limit: Int = 10) async -> [UnifiedContent] {
        return await search(query: query, limit: limit, contentTypes: [.document])
    }
    
    func searchMessages(query: String, limit: Int = 10) async -> [UnifiedContent] {
        return await search(query: query, limit: limit, contentTypes: [.message])
    }
    
    func searchEmails(query: String, limit: Int = 10) async -> [UnifiedContent] {
        return await search(query: query, limit: limit, contentTypes: [.email])
    }
    
    func searchNotes(query: String, limit: Int = 10) async -> [UnifiedContent] {
        return await search(query: query, limit: limit, contentTypes: [.note])
    }
    
    // MARK: - Error Handling
    
    func clearError() {
        error = nil
    }
}
