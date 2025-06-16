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
    let id: Int32
    let title: String
    let content: String
    let snippet: String
    let date: Date
    let distance: Double
    let metadata: [String: Any] // type-specific stuff
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
        // existing documents table
        let documentsSQL = """
        CREATE TABLE IF NOT EXISTS Document(
            Id INTEGER PRIMARY KEY AUTOINCREMENT,
            Title TEXT NOT NULL,
            Content TEXT NOT NULL,
            CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        """
        try execute(documentsSQL)
        
        // messages table
        let messagesSQL = """
        CREATE TABLE IF NOT EXISTS Message(
            Id INTEGER PRIMARY KEY AUTOINCREMENT,
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
            UNIQUE(OriginalId, ChatId)
        );
        """
        try execute(messagesSQL)
        print("✓ messages table ready")
        
        // emails table
        let emailsSQL = """
        CREATE TABLE IF NOT EXISTS Email(
            Id INTEGER PRIMARY KEY AUTOINCREMENT,
            OriginalId TEXT NOT NULL UNIQUE,
            ThreadId TEXT NOT NULL,
            Subject TEXT NOT NULL,
            Sender TEXT NOT NULL,
            Recipient TEXT NOT NULL,
            Date DATETIME NOT NULL,
            Content TEXT NOT NULL,
            Labels TEXT, -- json array as text
            Snippet TEXT,
            Timestamp INTEGER NOT NULL
        );
        """
        try execute(emailsSQL)
        print("✓ emails table ready")
        
        // notes table
        let notesSQL = """
        CREATE TABLE IF NOT EXISTS Note(
            Id INTEGER PRIMARY KEY AUTOINCREMENT,
            OriginalId INTEGER NOT NULL UNIQUE,
            Title TEXT NOT NULL,
            Snippet TEXT,
            Content TEXT NOT NULL,
            Folder TEXT NOT NULL,
            Created DATETIME,
            Modified DATETIME NOT NULL,
            CreationTimestamp REAL,
            ModificationTimestamp REAL NOT NULL
        );
        """
        try execute(notesSQL)
        print("✓ notes table ready")
        
        // unified embeddings table - references any content type
        let embeddingSQL = """
        CREATE VIRTUAL TABLE IF NOT EXISTS ContentEmbedding USING vec0(
            content_type TEXT,
            content_id INTEGER,
            embedding float[\(embeddingDimensions)]
        );
        """
        try execute(embeddingSQL)
        print("✓ content embeddings table ready")
        
        // chunks with embeddings - unified chunk storage
        let chunksSQL = """
        CREATE VIRTUAL TABLE IF NOT EXISTS Chunk USING vec0(
            content_type TEXT,
            content_id INTEGER,
            chunk_index INTEGER,
            +chunk_text TEXT,
            +start_offset INTEGER,
            +end_offset INTEGER,
            embedding float[\(embeddingDimensions)]
        );
        """
        try execute(chunksSQL)
        print("✓ chunks table ready")
        
        print("database setup complete ✨")
    }
    
    // MARK: - Unified Search
    
    func searchAllContent(queryEmbedding: [Float], limit: Int = 20, contentTypes: [ContentType] = ContentType.allCases) throws -> [UnifiedSearchResult] {
        // search embeddings first
        let placeholders = contentTypes.map { _ in "?" }.joined(separator: ",")
        let vectorSQL = """
        SELECT content_type, content_id, distance 
        FROM ContentEmbedding 
        WHERE content_type IN (\(placeholders)) 
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
            let contentType = String(cString: sqlite3_column_text(stmt, 0))
            let contentId = sqlite3_column_int(stmt, 1)
            let distance = sqlite3_column_double(stmt, 2)
            
            if let type = ContentType(rawValue: contentType),
               let result = try fetchUnifiedResult(type: type, id: contentId, distance: distance) {
                results.append(result)
            }
        }
        
        return results
    }
    
    private func fetchUnifiedResult(type: ContentType, id: Int32, distance: Double) throws -> UnifiedSearchResult? {
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
            // parse message date string to Date
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
            // parse email date string to Date
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
            // parse note date string to Date
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
    
    func insertMessage(_ message: MessageData) throws -> Int32 {
        let sql = """
        INSERT OR REPLACE INTO Message 
        (OriginalId, Text, Date, Timestamp, IsFromMe, IsSent, Service, Contact, ChatName, ChatId)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        
        guard sqlite3_bind_int(stmt, 1, message.originalId) == SQLITE_OK,
              sqlite3_bind_text(stmt, 2, message.text, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 3, message.date, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_int64(stmt, 4, message.timestamp) == SQLITE_OK,
              sqlite3_bind_int(stmt, 5, message.isFromMe ? 1 : 0) == SQLITE_OK,
              sqlite3_bind_int(stmt, 6, message.isSent ? 1 : 0) == SQLITE_OK,
              sqlite3_bind_text(stmt, 7, message.service, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 8, message.contact, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 9, message.chatName, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 10, message.chatId, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteError.step(message: errorMessage)
        }
        
        let newId = Int32(sqlite3_last_insert_rowid(dbPointer))
        print("inserted message with id: \(newId) (original: \(message.originalId))")
        return newId
    }
    
    func findMessage(id: Int32) throws -> MessageData? {
        let sql = "SELECT * FROM Message WHERE Id = ?;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_bind_int(stmt, 1, id) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return extractMessage(from: stmt)
        }
        return nil
    }
    
    // MARK: - Email Operations
    
    func insertEmail(_ email: EmailData) throws -> Int32 {
        let sql = """
        INSERT OR REPLACE INTO Email 
        (OriginalId, ThreadId, Subject, Sender, Recipient, Date, Content, Labels, Snippet, Timestamp)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let labelsJson = try? JSONSerialization.data(withJSONObject: email.labels, options: [])
        let labelsString = labelsJson.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        
        guard sqlite3_bind_text(stmt, 1, email.originalId, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 2, email.threadId, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 3, email.subject, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 4, email.sender, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 5, email.recipient, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 6, email.readableDate, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 7, email.content, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 8, labelsString, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 9, email.snippet, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_int64(stmt, 10, email.timestamp) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteError.step(message: errorMessage)
        }
        
        let newId = Int32(sqlite3_last_insert_rowid(dbPointer))
        print("inserted email with id: \(newId) (original: \(email.originalId))")
        return newId
    }
    
    func findEmail(id: Int32) throws -> EmailData? {
        let sql = "SELECT * FROM Email WHERE Id = ?;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_bind_int(stmt, 1, id) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return extractEmail(from: stmt)
        }
        return nil
    }
    
    // MARK: - Note Operations
    
    func insertNote(_ note: NoteData) throws -> Int32 {
        let sql = """
        INSERT OR REPLACE INTO Note 
        (OriginalId, Title, Snippet, Content, Folder, Created, Modified, CreationTimestamp, ModificationTimestamp)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        
        guard sqlite3_bind_int(stmt, 1, note.originalId) == SQLITE_OK,
              sqlite3_bind_text(stmt, 2, note.title, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 3, note.snippet, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 4, note.content, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 5, note.folder, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        // handle nullable dates
        if let created = note.created {
            guard sqlite3_bind_text(stmt, 6, created, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
                throw SQLiteError.bind(message: errorMessage)
            }
        } else {
            guard sqlite3_bind_null(stmt, 6) == SQLITE_OK else {
                throw SQLiteError.bind(message: errorMessage)
            }
        }
        
        guard sqlite3_bind_text(stmt, 7, note.modified, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        // handle nullable timestamps
        if let creationTs = note.creationTimestamp {
            guard sqlite3_bind_double(stmt, 8, creationTs) == SQLITE_OK else {
                throw SQLiteError.bind(message: errorMessage)
            }
        } else {
            guard sqlite3_bind_null(stmt, 8) == SQLITE_OK else {
                throw SQLiteError.bind(message: errorMessage)
            }
        }
        
        guard sqlite3_bind_double(stmt, 9, note.modificationTimestamp) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteError.step(message: errorMessage)
        }
        
        let newId = Int32(sqlite3_last_insert_rowid(dbPointer))
        print("inserted note with id: \(newId) (original: \(note.originalId))")
        return newId
    }
    
    func findNote(id: Int32) throws -> NoteData? {
        let sql = "SELECT * FROM Note WHERE Id = ?;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_bind_int(stmt, 1, id) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return extractNote(from: stmt)
        }
        return nil
    }
    
    // MARK: - Embedding Operations
    
    func insertContentEmbedding(type: ContentType, contentId: Int32, embedding: [Float]) throws {
        let sql = "INSERT OR REPLACE INTO ContentEmbedding(content_type, content_id, embedding) VALUES (?, ?, vec_f32(?));"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let vectorBlob = embeddingToBlob(embedding)
        
        guard sqlite3_bind_text(stmt, 1, type.rawValue, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_int(stmt, 2, contentId) == SQLITE_OK,
              sqlite3_bind_blob(stmt, 3, vectorBlob, Int32(vectorBlob.count), nil) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteError.step(message: errorMessage)
        }
    }
    
    // MARK: - Chunk Operations (for future use)
    
    func insertChunk(type: ContentType, contentId: Int32, chunkIndex: Int, text: String, startOffset: Int? = nil, endOffset: Int? = nil) throws -> Int32 {
        let sql = """
        INSERT INTO Chunk 
        (content_type, content_id, chunk_index, chunk_text, start_offset, end_offset, embedding)
        VALUES (?, ?, ?, ?, ?, ?, vec_f32(?));
        """
        
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        
        // for now, create a dummy embedding - you'll want to pass this in later
        let dummyEmbedding = Array(repeating: Float(0.0), count: embeddingDimensions)
        let vectorBlob = embeddingToBlob(dummyEmbedding)
        
        guard sqlite3_bind_text(stmt, 1, type.rawValue, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_int(stmt, 2, contentId) == SQLITE_OK,
              sqlite3_bind_int(stmt, 3, Int32(chunkIndex)) == SQLITE_OK,
              sqlite3_bind_text(stmt, 4, text, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        // bind optional offsets
        if let start = startOffset {
            guard sqlite3_bind_int(stmt, 5, Int32(start)) == SQLITE_OK else {
                throw SQLiteError.bind(message: errorMessage)
            }
        } else {
            guard sqlite3_bind_null(stmt, 5) == SQLITE_OK else {
                throw SQLiteError.bind(message: errorMessage)
            }
        }
        
        if let end = endOffset {
            guard sqlite3_bind_int(stmt, 6, Int32(end)) == SQLITE_OK else {
                throw SQLiteError.bind(message: errorMessage)
            }
        } else {
            guard sqlite3_bind_null(stmt, 6) == SQLITE_OK else {
                throw SQLiteError.bind(message: errorMessage)
            }
        }
        
        guard sqlite3_bind_blob(stmt, 7, vectorBlob, Int32(vectorBlob.count), nil) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteError.step(message: errorMessage)
        }
        
        return Int32(sqlite3_last_insert_rowid(dbPointer))
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
        let id = sqlite3_column_int(stmt, 0)
        let title = String(cString: sqlite3_column_text(stmt, 1))
        let content = String(cString: sqlite3_column_text(stmt, 2))
        
        let dateString = String(cString: sqlite3_column_text(stmt, 3))
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: dateString) ?? Date()
        
        return Document(id: id, title: title, content: content, createdAt: date)
    }
    
    private func extractMessage(from stmt: OpaquePointer?) -> MessageData {
        let id = sqlite3_column_int(stmt, 0) // our auto-increment id
        let originalId = sqlite3_column_int(stmt, 1) // their original id
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
        let id = sqlite3_column_int(stmt, 0) // our auto-increment id
        let originalId = String(cString: sqlite3_column_text(stmt, 1)) // their original string id
        let threadId = String(cString: sqlite3_column_text(stmt, 2))
        let subject = String(cString: sqlite3_column_text(stmt, 3))
        let sender = String(cString: sqlite3_column_text(stmt, 4))
        let recipient = String(cString: sqlite3_column_text(stmt, 5))
        let date = String(cString: sqlite3_column_text(stmt, 6))
        let content = String(cString: sqlite3_column_text(stmt, 7))
        let labelsString = String(cString: sqlite3_column_text(stmt, 8))
        let snippet = String(cString: sqlite3_column_text(stmt, 9))
        let timestamp = sqlite3_column_int64(stmt, 10)
        
        // parse labels json
        let labels = (try? JSONSerialization.jsonObject(with: labelsString.data(using: .utf8) ?? Data()) as? [String]) ?? []
        
        return EmailData(
            id: id, originalId: originalId, threadId: threadId, subject: subject, sender: sender,
            recipient: recipient, date: date, content: content, labels: labels,
            snippet: snippet, readableDate: date, timestamp: timestamp
        )
    }
    
    private func extractNote(from stmt: OpaquePointer?) -> NoteData {
        let id = sqlite3_column_int(stmt, 0) // our auto-increment id
        let originalId = sqlite3_column_int(stmt, 1) // their original int id
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
    
    func insertDocument(title: String, content: String, embedding: [Float]) throws -> Int32 {
        // insert document
        let docSQL = "INSERT INTO Document (Title, Content) VALUES (?, ?);"
        let stmt = try prepare(docSQL)
        defer { sqlite3_finalize(stmt) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(stmt, 1, title, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 2, content, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteError.step(message: errorMessage)
        }
        
        let documentId = sqlite3_last_insert_rowid(dbPointer)
        
        // insert into unified embedding table
        try insertContentEmbedding(type: .document, contentId: Int32(documentId), embedding: embedding)
        
        return Int32(documentId)
    }
    
    func findDocument(id: Int32) throws -> Document? {
        let sql = "SELECT Id, Title, Content, CreatedAt FROM Document WHERE Id = ?;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_bind_int(stmt, 1, id) == SQLITE_OK else {
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
    let id: Int32? // our db id
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
    let id: Int32? // our db id
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
    let id: Int32? // our db id
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
