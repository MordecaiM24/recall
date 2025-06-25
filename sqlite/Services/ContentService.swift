//
//  ContentService.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/24/25.
//

import Foundation


final class ContentService: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    private let sqlite: SQLiteService
    private let embedding: EmbeddingService
    
    init(sqlite: SQLiteService, embedding: EmbeddingService) {
        self.sqlite = sqlite
        self.embedding = embedding
    }
    
    // single entry point for writes
    func add(_ item: Item) async throws -> String {
        isLoading = true; defer { isLoading = false }
        switch item.type {
        case .document:
            return try sqlite.insertDocument(Document(id: item.id, title: item.title, content: item.content, createdAt: item.date))
        case .message:
            return try sqlite.insertMessage(Message(
                id: item.id,
                originalId: item.metadata["originalId"] as? Int32 ?? 0,
                text: item.content,
                date: item.date,
                timestamp: item.metadata["timestamp"] as? Int64 ?? 0,
                isFromMe: item.metadata["isFromMe"] as? Bool ?? false,
                isSent: item.metadata["isSent"] as? Bool ?? false,
                service: item.metadata["service"] as? String ?? "",
                contact: item.metadata["contact"] as? String ?? "",
                chatName: item.metadata["chatName"] as? String,
                chatId: item.metadata["chatId"] as? String,
                contactNumber: item.metadata["contactNumber"] as? String,
                createdAt: item.metadata["createdAt"] as? Date ?? item.date
            ))
        case .email:
            return try sqlite.insertEmail(Email(
                id: item.id,
                originalId: item.metadata["originalId"] as? String ?? "",
                threadId: item.threadId,
                subject: item.title,
                sender: item.metadata["sender"] as? String ?? "",
                recipient: item.metadata["recipient"] as? String ?? "",
                date: item.date,
                content: item.content,
                labels: item.metadata["labels"] as? [String] ?? [],
                snippet: item.snippet,
                timestamp: item.metadata["timestamp"] as? Int64 ?? 0,
                createdAt: item.metadata["createdAt"] as? Date ?? item.date
            ))
        case .note:
            return try sqlite.insertNote(Note(
                id: item.id,
                originalId: item.metadata["originalId"] as? Int32 ?? 0,
                title: item.title,
                snippet: item.snippet,
                content: item.content,
                folder: item.metadata["folder"] as? String ?? "",
                created: item.metadata["created"] as? Date,
                modified: item.date,
                creationTimestamp: item.metadata["creationTimestamp"] as? Double,
                modificationTimestamp: item.metadata["modificationTimestamp"] as? Double ?? 0,
                createdAt: item.metadata["createdAt"] as? Date ?? item.date
            ))
        }
    }
    
    // single entry point for (inefficient) batch writes
    func add(_ items: [Item]) async throws -> [String] {
        var ids: [String] = []
        for item in items {
            ids.append(try await add(item))
        }
        return ids
    }
    
    // single entry point for reads
    func all(_ type: ContentType) async throws -> [Item] {
        switch type {
        case .document: return try sqlite.getAllDocuments().map(Item.init(from:))
        case .message: return try sqlite.getAllMessages().map(Item.init(from:))
        case .email: return try sqlite.getAllEmails().map(Item.init(from:))
        case .note: return try sqlite.getAllNotes().map(Item.init(from:))
        }
    }
    
    func one(_ type: ContentType, id: String) async throws -> Item? {
        switch type {
        case .document: return try sqlite.findDocument(id: id).map(Item.init(from:))
        case .message: return try sqlite.findMessage(id: id).map(Item.init(from:))
        case .email: return try sqlite.findEmail(id: id).map(Item.init(from:))
        case .note: return try sqlite.findNote(id: id).map(Item.init(from:))
        }
    }
    
    
    // not a fan of the lack of DRY here but what can ya do
    
    // TODO: improve atomicity here
    // TODO: put embedding on background thread
    func importEmails(_ emails: [Email]) async throws -> [String] {
        print("inserting emails")
        let emailIds = try sqlite.insertEmails(emails)
        print("inserted \(emailIds.count) emails")
        let items = emails.map { Item(from: $0) }
        print("generated \(items.count) items from emails")
        
        try await createThreads(from: items)
        print("inserted threads")
        
        return emailIds
    }
    
    func importMessages(_ messages: [Message]) async throws -> [String] {
        let messageIds = try sqlite.insertMessages(messages)
        let items = messages.map { Item(from: $0) }
        
        try await createThreads(from: items)
        
        return messageIds
    }
    
    func importNotes(_ notes: [Note]) async throws -> [String] {
        let noteIds = try sqlite.insertNotes(notes)
        let items = notes.map { Item(from: $0 ) }
        
        try await createThreads(from: items)
        
        return noteIds
    }
    
    func importDocuments(_ documents: [Document]) async throws -> [String] {
        let documentIds = try sqlite.insertDocuments(documents)
        let items = documents.map { Item(from: $0) }
        
        try await createThreads(from: items)
        
        return documentIds
    }
    
    func createThreads(from items: [Item]) async throws {
        print("starting thread creation")
        let grouped = Dictionary(grouping: items, by: { $0.threadId })
        let itemGroups = Array(grouped.values)
        print("created \(itemGroups.count) thread groups")
        
        let threads = try itemGroups.map { try Thread(from: $0) }
        print("created \(threads.count) threads")
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for thread in threads {
                group.addTask {
                    let chunks = try await self.embedding.createThreadChunks(from: thread)
                    try self.sqlite.insertThread(thread)
                    try self.sqlite.insertThreadChunks(chunks)
                }
            }
            
            try await group.waitForAll()
        }
    }
}
