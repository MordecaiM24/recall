//
//  ContentService.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/24/25.
//

import Foundation

enum ordering {
    case createdAtAsc
    case createdAtDesc
    case dateAsc
    case dateDesc
    case titleAsc
    case titleDesc
    
    var sql: String {
        switch self {
        case .createdAtAsc: return "created_at ASC"
        case .createdAtDesc: return "created_at DESC"
        case .dateAsc: return "date ASC"
        case .dateDesc: return "date DESC"
        case .titleAsc: return "title ASC"
        case .titleDesc: return "title DESC"
        }
    }
}

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
    
    // single entry point for paginated, etc reads
    func all(
        _ type: ContentType?,
        limit: Int? = nil,
        offset: Int? = nil,
        orderBy: ordering? = nil
    ) async throws -> [Item] {
        switch type {
        case .document:
            return try sqlite.getAllDocuments(limit: limit, offset: offset, orderBy: orderBy?.sql).map(Item.init(from:))
        case .message:
            return try sqlite.getAllMessages(limit: limit, offset: offset, orderBy: orderBy?.sql).map(Item.init(from:))
        case .email:
            return try sqlite.getAllEmails(limit: limit, offset: offset, orderBy: orderBy?.sql).map(Item.init(from:))
        case .note:
            return try sqlite.getAllNotes(limit: limit, offset: offset, orderBy: orderBy?.sql).map(Item.init(from:))
        default:
            return try sqlite.getAllItems(limit: limit, offset: offset, orderBy: orderBy?.sql)
        }
    }
    
    func one(_ type: ContentType?, id: String) async throws -> Item? {
        switch type {
        case .document: return try sqlite.findDocument(id: id).map(Item.init(from:))
        case .message: return try sqlite.findMessage(id: id).map(Item.init(from:))
        case .email: return try sqlite.findEmail(id: id).map(Item.init(from:))
        case .note: return try sqlite.findNote(id: id).map(Item.init(from:))
        default: return try sqlite.findItem(id: id)
        }
    }
    
    func byThreadId(_ threadId: String, type: ContentType? = nil, limit: Int? = nil,
                    offset: Int? = nil,
                    orderBy: ordering? = nil) async throws -> [Item] {
        print("getting items by thread \(threadId)")
        return try sqlite.getItemsByThreadId(threadId, type: type?.rawValue, limit: limit, offset: offset, orderBy: orderBy?.sql)
    }
    
    
    func search(_ query: String) async throws -> [SearchResult] {
        let queryEmbedding = try await embedding.embed(text: query)
        return try sqlite.searchThreadChunks(queryEmbedding: queryEmbedding)
    }
    
    // not a fan of the lack of DRY here but what can ya do
    
    // TODO: improve atomicity here
    // TODO: put embedding on background thread
    func importEmails(_ emails: [Email]) async throws -> [String] {
        let emailIds = try sqlite.insertEmails(emails)
        let items = emails.map { Item(from: $0) }
        
        try await createThreads(from: items)
        
        return emailIds
    }
    
    func importMessages(_ messages: [Message]) async throws -> [String] {
        print("importing \(messages.count) messages")
        let messageIds = try sqlite.insertMessages(messages)
        print("inserted \(messageIds.count) messages")
        let items = messages.map { Item(from: $0) }
        print("creating items from messages")
        
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
        // this is completely unimportant - it was autocomplete generated, just thought it was funny
        // let queue = DispatchQueue(label: "com.github.jakeheiser.mailbox.import-threads")
        let grouped = Dictionary(grouping: items, by: { $0.threadId })
        let itemGroups = Array(grouped.values)
        
        let threads = try itemGroups.map { try Thread(from: $0) }
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for thread in threads {
                // again! this is glue - change this if possible. threadId is going to be reassigned before we insert into db
                // but original thread id's based on the imported data type should be separate from the db generated uuid we're creating.
                
                var dbItems = items.filter { $0.threadId == thread.threadId }
                dbItems = dbItems.map { item in
                    var newItem = item
                    newItem.threadId = thread.id
                    return newItem
                }
                
                group.addTask {
                    let chunks = try await self.embedding.createThreadChunks(from: thread)
                    _ = try self.sqlite.insertThread(thread)
                    _ = try self.sqlite.insertItems(dbItems)
                    _ = try self.sqlite.insertThreadChunks(chunks)
                }
            }
            
            try await group.waitForAll()
        }
    }
}
