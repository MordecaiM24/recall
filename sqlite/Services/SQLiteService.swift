//
//  SQLiteService.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 5/25/25.
//

import Foundation
import SQLite3

enum SQLiteError: Error {
    case openDatabase(message: String)
    case prepare(message: String)
    case step(message: String)
    case bind(message: String)
    case initExtension(message: String)
}

enum ContentType: String, CaseIterable {
    case document = "document"
    case message = "message"
    case email = "email"
    case note = "note"
    
    var tableName: String {
        switch self {
        case .document: return "Document"
        case .message: return "Message"
        case .email: return "Email"
        case .note: return "Note"
        }
    }
}

// unified search result
struct UnifiedSearchResult {
    let type: ContentType
    let id: String // now UUID
    let title: String
    let content: String
    let snippet: String
    let date: Date
    let distance: Double
    let metadata: [String: Any]
}

final class SQLiteService {
    private let dbPointer: OpaquePointer?
    private let embeddingDimensions: Int
    
    init(path: String = defaultDBPath, embeddingDimensions: Int = 384) throws {
        self.embeddingDimensions = embeddingDimensions
        
        // migrate-destroy if schema version changed
        let defaults = UserDefaults.standard
        let previous = defaults.integer(forKey: databaseVersionKey)
        if previous != schemaVersion {
            try? FileManager.default.removeItem(atPath: path)
            defaults.set(schemaVersion, forKey: databaseVersionKey)
        }

        var db: OpaquePointer?
        if sqlite3_open(path, &db) == SQLITE_OK {
            self.dbPointer = db
            
            // load sqlite-vec extension
            if sqlite3_vec_init(db, nil, nil) != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(db))
                throw SQLiteError.initExtension(message: msg)
            }
        } else {
            defer { if db != nil { sqlite3_close(db) } }
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "no error"
            throw SQLiteError.openDatabase(message: msg)
        }
    }

    deinit {
        sqlite3_close(dbPointer)
    }

    private var errorMessage: String {
        if let ptr = sqlite3_errmsg(dbPointer) {
            return String(cString: ptr)
        }
        return "no error"
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(dbPointer, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepare(message: errorMessage)
        }
        return stmt
    }

    func execute(_ sql: String) throws {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteError.step(message: errorMessage)
        }
    }
    
    // MARK: - Database Setup
    
    func setupDatabase() throws {
        // documents table with UUID
        let documentsSQL = """
        CREATE TABLE IF NOT EXISTS Document(
            Id TEXT PRIMARY KEY,
            Title TEXT NOT NULL,
            Content TEXT NOT NULL,
            CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        """
        try execute(documentsSQL)
        
        // messages table with UUID
        let messagesSQL = """
        CREATE TABLE IF NOT EXISTS Message(
            Id TEXT PRIMARY KEY,
            OriginalId INTEGER NOT NULL,
            Text TEXT NOT NULL,
            Date DATETIME NOT NULL,
            Timestamp INTEGER NOT NULL,
            IsFromMe BOOLEAN NOT NULL,
            IsSent BOOLEAN NOT NULL,
            Service TEXT NOT NULL,
            Contact TEXT,
            ChatName TEXT,
            ChatId TEXT NOT NULL,
            CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(OriginalId, ChatId)
        );
        """
        try execute(messagesSQL)
        print("✓ messages table ready")
        
        // emails table with UUID
        let emailsSQL = """
        CREATE TABLE IF NOT EXISTS Email(
            Id TEXT PRIMARY KEY,
            OriginalId TEXT NOT NULL UNIQUE,
            ThreadId TEXT NOT NULL,
            Subject TEXT NOT NULL,
            Sender TEXT NOT NULL,
            Recipient TEXT NOT NULL,
            Date DATETIME NOT NULL,
            Content TEXT NOT NULL,
            Labels TEXT,
            Snippet TEXT,
            Timestamp INTEGER NOT NULL,
            CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        """
        try execute(emailsSQL)
        print("✓ emails table ready")
        
        // notes table with UUID
        let notesSQL = """
        CREATE TABLE IF NOT EXISTS Note(
            Id TEXT PRIMARY KEY,
            OriginalId INTEGER NOT NULL UNIQUE,
            Title TEXT NOT NULL,
            Snippet TEXT,
            Content TEXT NOT NULL,
            Folder TEXT NOT NULL,
            Created DATETIME,
            Modified DATETIME NOT NULL,
            CreationTimestamp REAL,
            ModificationTimestamp REAL NOT NULL,
            CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        """
        try execute(notesSQL)
        print("✓ notes table ready")
        
        // single chunk virtual table for all content
        let chunkSQL = """
        CREATE VIRTUAL TABLE IF NOT EXISTS Chunk USING vec0(
            parent_id TEXT,
            content_type TEXT,
            chunk_index INTEGER,
            +chunk_text TEXT,
            embedding float[\(embeddingDimensions)]
        );
        """
        try execute(chunkSQL)
        print("✓ chunk table ready")
        
        print("database setup complete ✨")
    }
    
    // MARK: - UUID Generation
    
    private func generateUUID() -> String {
        return UUID().uuidString
    }
    
    // MARK: - Unified Search
    
    func searchAllContent(queryEmbedding: [Float], limit: Int = 20, contentTypes: [ContentType] = ContentType.allCases) throws -> [UnifiedSearchResult] {
        let placeholders = contentTypes.map { _ in "?" }.joined(separator: ",")
        let vectorSQL = """
        SELECT parent_id, content_type, distance 
        FROM Chunk 
        WHERE content_type IN (\(placeholders)) 
        AND chunk_index = 0
        AND embedding MATCH vec_f32(?) 
        ORDER BY distance 
        LIMIT ?;
        """
        
        let stmt = try prepare(vectorSQL)
        defer { sqlite3_finalize(stmt) }
        
        // bind content types
        for (index, contentType) in contentTypes.enumerated() {
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            guard sqlite3_bind_text(stmt, Int32(index + 1), contentType.rawValue, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
                throw SQLiteError.bind(message: errorMessage)
            }
        }
        
        // bind embedding and limit
        let vectorBlob = embeddingToBlob(queryEmbedding)
        guard sqlite3_bind_blob(stmt, Int32(contentTypes.count + 1), vectorBlob, Int32(vectorBlob.count), nil) == SQLITE_OK,
              sqlite3_bind_int(stmt, Int32(contentTypes.count + 2), Int32(limit)) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        var results = [UnifiedSearchResult]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let parentId = String(cString: sqlite3_column_text(stmt, 0))
            let contentType = String(cString: sqlite3_column_text(stmt, 1))
            let distance = sqlite3_column_double(stmt, 2)
            
            if let type = ContentType(rawValue: contentType),
               let result = try fetchUnifiedResult(type: type, id: parentId, distance: distance) {
                results.append(result)
            }
        }
        
        return results
    }
    
    private func fetchUnifiedResult(type: ContentType, id: String, distance: Double) throws -> UnifiedSearchResult? {
        switch type {
        case .document:
            guard let doc = try findDocument(id: id) else {
                print("failed to find document with id: \(id)")
                return nil
            }
            return UnifiedSearchResult(
                type: .document,
                id: id,
                title: doc.title,
                content: doc.content,
                snippet: String(doc.content.prefix(200)),
                date: doc.createdAt,
                distance: distance,
                metadata: [:]
            )
            
        case .message:
            guard let msg = try findMessage(id: id) else {
                print("failed to find message with id: \(id)")
                return nil
            }
            let messageDate = parseMessageDate(msg.date) ?? Date(timeIntervalSince1970: Double(msg.timestamp) / 1_000_000_000)
            return UnifiedSearchResult(
                type: .message,
                id: id,
                title: msg.chatName.isEmpty ? msg.chatId : msg.chatName,
                content: msg.text,
                snippet: msg.text,
                date: messageDate,
                distance: distance,
                metadata: [
                    "isFromMe": msg.isFromMe,
                    "service": msg.service,
                    "contact": msg.contact ?? "",
                    "chatId": msg.chatId
                ]
            )
            
        case .email:
            guard let email = try findEmail(id: id) else {
                print("failed to find email with id: \(id)")
                return nil
            }
            let emailDate = parseEmailDate(email.readableDate) ?? Date(timeIntervalSince1970: Double(email.timestamp))
            return UnifiedSearchResult(
                type: .email,
                id: id,
                title: email.subject,
                content: email.content,
                snippet: email.snippet,
                date: emailDate,
                distance: distance,
                metadata: [
                    "sender": email.sender,
                    "recipient": email.recipient,
                    "threadId": email.threadId,
                    "labels": email.labels
                ]
            )
            
        case .note:
            guard let note = try findNote(id: id) else {
                print("failed to find note with id: \(id)")
                return nil
            }
            let noteDate = parseNoteDate(note.modified) ?? Date(timeIntervalSinceReferenceDate: note.modificationTimestamp)
            return UnifiedSearchResult(
                type: .note,
                id: id,
                title: note.title,
                content: note.content,
                snippet: note.snippet ?? String(note.content.prefix(200)),
                date: noteDate,
                distance: distance,
                metadata: [
                    "folder": note.folder,
                    "created": note.created != nil ? parseNoteDate(note.created!)?.timeIntervalSince1970 ?? 0 : 0
                ]
            )
        }
    }
    
    // MARK: - Date Parsing Helpers
    
    private func parseMessageDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: dateString)
    }
    
    private func parseEmailDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString)
    }
    
    private func parseNoteDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: dateString)
    }
    
    // MARK: - Message Operations
    
    func insertMessage(_ message: MessageData) throws -> String {
        let messageId = generateUUID()
        
        let sql = """
        INSERT OR REPLACE INTO Message 
        (Id, OriginalId, Text, Date, Timestamp, IsFromMe, IsSent, Service, Contact, ChatName, ChatId)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        
        guard sqlite3_bind_text(stmt, 1, messageId, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_int(stmt, 2, message.originalId) == SQLITE_OK,
              sqlite3_bind_text(stmt, 3, message.text, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 4, message.date, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_int64(stmt, 5, message.timestamp) == SQLITE_OK,
              sqlite3_bind_int(stmt, 6, message.isFromMe ? 1 : 0) == SQLITE_OK,
              sqlite3_bind_int(stmt, 7, message.isSent ? 1 : 0) == SQLITE_OK,
              sqlite3_bind_text(stmt, 8, message.service, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 9, message.contact, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 10, message.chatName, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 11, message.chatId, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteError.step(message: errorMessage)
        }
        
        print("inserted message with id: \(messageId) (original: \(message.originalId))")
        return messageId
    }
    
    func findMessage(id: String) throws -> MessageData? {
        let sql = "SELECT * FROM Message WHERE Id = ?;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return extractMessage(from: stmt)
        }
        return nil
    }
    
    // MARK: - Email Operations
    
    func insertEmail(_ email: EmailData) throws -> String {
        let emailId = generateUUID()
        
        let sql = """
        INSERT OR REPLACE INTO Email 
        (Id, OriginalId, ThreadId, Subject, Sender, Recipient, Date, Content, Labels, Snippet, Timestamp)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let labelsJson = try? JSONSerialization.data(withJSONObject: email.labels, options: [])
        let labelsString = labelsJson.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        
        guard sqlite3_bind_text(stmt, 1, emailId, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 2, email.originalId, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 3, email.threadId, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 4, email.subject, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 5, email.sender, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 6, email.recipient, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 7, email.readableDate, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 8, email.content, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 9, labelsString, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 10, email.snippet, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_int64(stmt, 11, email.timestamp) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteError.step(message: errorMessage)
        }
        
        print("inserted email with id: \(emailId) (original: \(email.originalId))")
        return emailId
    }
    
    func findEmail(id: String) throws -> EmailData? {
        let sql = "SELECT * FROM Email WHERE Id = ?;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return extractEmail(from: stmt)
        }
        return nil
    }
    
    // MARK: - Note Operations
    
    func insertNote(_ note: NoteData) throws -> String {
        let noteId = generateUUID()
        
        let sql = """
        INSERT OR REPLACE INTO Note 
        (Id, OriginalId, Title, Snippet, Content, Folder, Created, Modified, CreationTimestamp, ModificationTimestamp)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        
        guard sqlite3_bind_text(stmt, 1, noteId, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_int(stmt, 2, note.originalId) == SQLITE_OK,
              sqlite3_bind_text(stmt, 3, note.title, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 4, note.snippet, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 5, note.content, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 6, note.folder, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        // handle nullable dates
        if let created = note.created {
            guard sqlite3_bind_text(stmt, 7, created, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
                throw SQLiteError.bind(message: errorMessage)
            }
        } else {
            guard sqlite3_bind_null(stmt, 7) == SQLITE_OK else {
                throw SQLiteError.bind(message: errorMessage)
            }
        }
        
        guard sqlite3_bind_text(stmt, 8, note.modified, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        // handle nullable timestamps
        if let creationTs = note.creationTimestamp {
            guard sqlite3_bind_double(stmt, 9, creationTs) == SQLITE_OK else {
                throw SQLiteError.bind(message: errorMessage)
            }
        } else {
            guard sqlite3_bind_null(stmt, 9) == SQLITE_OK else {
                throw SQLiteError.bind(message: errorMessage)
            }
        }
        
        guard sqlite3_bind_double(stmt, 10, note.modificationTimestamp) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteError.step(message: errorMessage)
        }
        
        print("inserted note with id: \(noteId) (original: \(note.originalId))")
        return noteId
    }
    
    func findNote(id: String) throws -> NoteData? {
        let sql = "SELECT * FROM Note WHERE Id = ?;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return extractNote(from: stmt)
        }
        return nil
    }
    
    // MARK: - Chunk Operations
    
    func insertChunk(parentId: String, contentType: ContentType, chunkIndex: Int = 0, text: String, embedding: [Float]) throws {
        let sql = """
        INSERT INTO Chunk 
        (parent_id, content_type, chunk_index, chunk_text, embedding)
        VALUES (?, ?, ?, ?, vec_f32(?));
        """
        
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let vectorBlob = embeddingToBlob(embedding)
        
        guard sqlite3_bind_text(stmt, 1, parentId, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 2, contentType.rawValue, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_int(stmt, 3, Int32(chunkIndex)) == SQLITE_OK,
              sqlite3_bind_text(stmt, 4, text, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_blob(stmt, 5, vectorBlob, Int32(vectorBlob.count), nil) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteError.step(message: errorMessage)
        }
    }
    

    
    // MARK: - Private Helpers
    
    private func embeddingToBlob(_ embedding: [Float]) -> [UInt8] {
        var blob = [UInt8]()
        blob.reserveCapacity(embedding.count * 4)
        
        for value in embedding {
            let bits = value.bitPattern
            blob.append(UInt8(bits & 0xFF))
            blob.append(UInt8((bits >> 8) & 0xFF))
            blob.append(UInt8((bits >> 16) & 0xFF))
            blob.append(UInt8((bits >> 24) & 0xFF))
        }
        
        return blob
    }
    
    private func extractDocument(from stmt: OpaquePointer?) -> Document {
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let title = String(cString: sqlite3_column_text(stmt, 1))
        let content = String(cString: sqlite3_column_text(stmt, 2))
        
        let dateString = String(cString: sqlite3_column_text(stmt, 3))
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: dateString) ?? Date()
        
        return Document(id: id, title: title, content: content, createdAt: date)
    }
    
    private func extractMessage(from stmt: OpaquePointer?) -> MessageData {
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let originalId = sqlite3_column_int(stmt, 1)
        let text = String(cString: sqlite3_column_text(stmt, 2))
        let date = String(cString: sqlite3_column_text(stmt, 3))
        let timestamp = sqlite3_column_int64(stmt, 4)
        let isFromMe = sqlite3_column_int(stmt, 5) == 1
        let isSent = sqlite3_column_int(stmt, 6) == 1
        let service = String(cString: sqlite3_column_text(stmt, 7))
        let contact = sqlite3_column_text(stmt, 8).map { String(cString: $0) }
        let chatName = String(cString: sqlite3_column_text(stmt, 9))
        let chatId = String(cString: sqlite3_column_text(stmt, 10))
        
        return MessageData(
            id: id, originalId: originalId, text: text, date: date, timestamp: timestamp,
            isFromMe: isFromMe, isSent: isSent, service: service,
            contact: contact, chatName: chatName, chatId: chatId
        )
    }
    
    private func extractEmail(from stmt: OpaquePointer?) -> EmailData {
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let originalId = String(cString: sqlite3_column_text(stmt, 1))
        let threadId = String(cString: sqlite3_column_text(stmt, 2))
        let subject = String(cString: sqlite3_column_text(stmt, 3))
        let sender = String(cString: sqlite3_column_text(stmt, 4))
        let recipient = String(cString: sqlite3_column_text(stmt, 5))
        let readableDate = String(cString: sqlite3_column_text(stmt, 6))
        let content = String(cString: sqlite3_column_text(stmt, 7))
        let labelsString = String(cString: sqlite3_column_text(stmt, 8))
        let snippet = String(cString: sqlite3_column_text(stmt, 9))
        let timestamp = sqlite3_column_int64(stmt, 10)
        
        // parse labels json
        let labels = (try? JSONSerialization.jsonObject(with: labelsString.data(using: .utf8) ?? Data()) as? [String]) ?? []
        
        return EmailData(
            id: id, originalId: originalId, threadId: threadId, subject: subject, sender: sender,
            recipient: recipient, date: readableDate, content: content, labels: labels,
            snippet: snippet, readableDate: readableDate, timestamp: timestamp
        )
    }
    
    private func extractNote(from stmt: OpaquePointer?) -> NoteData {
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let originalId = sqlite3_column_int(stmt, 1)
        let title = String(cString: sqlite3_column_text(stmt, 2))
        let snippet = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
        let content = String(cString: sqlite3_column_text(stmt, 4))
        let folder = String(cString: sqlite3_column_text(stmt, 5))
        let created = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
        let modified = String(cString: sqlite3_column_text(stmt, 7))
        let creationTimestamp = sqlite3_column_type(stmt, 8) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 8)
        let modificationTimestamp = sqlite3_column_double(stmt, 9)
        
        return NoteData(
            id: id, originalId: originalId, title: title, snippet: snippet, content: content,
            folder: folder, created: created, modified: modified,
            creationTimestamp: creationTimestamp, modificationTimestamp: modificationTimestamp
        )
    }
    
    // MARK: - Legacy Document Support
    
    func insertDocument(title: String, content: String, embedding: [Float]) throws -> String {
        let documentId = generateUUID()
        
        // insert document
        let docSQL = "INSERT INTO Document (Id, Title, Content) VALUES (?, ?, ?);"
        let stmt = try prepare(docSQL)
        defer { sqlite3_finalize(stmt) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(stmt, 1, documentId, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 2, title, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 3, content, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteError.step(message: errorMessage)
        }
        
        // insert into chunk table
        try insertChunk(parentId: documentId, contentType: .document, chunkIndex: 0, text: content, embedding: embedding)
        
        return documentId
    }
    
    func findDocument(id: String) throws -> Document? {
        let sql = "SELECT Id, Title, Content, CreatedAt FROM Document WHERE Id = ?;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return extractDocument(from: stmt)
        }
        return nil
    }
    
    func findAllDocuments() throws -> [Document] {
        let sql = "SELECT Id, Title, Content, CreatedAt FROM Document ORDER BY CreatedAt DESC;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        var documents = [Document]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            documents.append(extractDocument(from: stmt))
        }
        return documents
    }
    
    func searchDocuments(queryEmbedding: [Float], limit: Int = 10) throws -> [SearchResult] {
        let results = try searchAllContent(queryEmbedding: queryEmbedding, limit: limit, contentTypes: [.document])
        return results.compactMap { result in
            guard let doc = try? findDocument(id: result.id) else { return nil }
            return SearchResult(document: doc, distance: result.distance)
        }
    }
}

// MARK: - Data Models

struct MessageData {
    let id: String? // our db id (now UUID)
    let originalId: Int32 // their id
    let text: String
    let date: String
    let timestamp: Int64
    let isFromMe: Bool
    let isSent: Bool
    let service: String
    let contact: String?
    let chatName: String
    let chatId: String
}

struct EmailData {
    let id: String? // our db id (now UUID)
    let originalId: String // their id
    let threadId: String
    let subject: String
    let sender: String
    let recipient: String
    let date: String
    let content: String
    let labels: [String]
    let snippet: String
    let readableDate: String
    let timestamp: Int64
}

struct NoteData {
    let id: String? // our db id (now UUID)
    let originalId: Int32 // their id
    let title: String
    let snippet: String?
    let content: String
    let folder: String
    let created: String?
    let modified: String
    let creationTimestamp: Double?
    let modificationTimestamp: Double
}
