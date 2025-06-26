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

// not very DRY. could probably implement generics. maybe slightly better for performance this way (prep and all)? whatever.

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
            
            if sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil) != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(db))
                throw SQLiteError.openDatabase(message: "Failed to set WAL mode: \(msg)")
            }
            
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
    
    
    
    // MARK: - Database Setup
    
    func setupDatabase() throws {
        let documentsSQL = """
        CREATE TABLE IF NOT EXISTS Document(
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        """
        try execute(documentsSQL)
        print("documents table ready")
        
        try execute("CREATE INDEX IF NOT EXISTS idx_document_id ON Document(id);")
        print("document index ready")
        
        let emailsSQL = """
        CREATE TABLE IF NOT EXISTS Email(
            id TEXT PRIMARY KEY,
            original_id TEXT NOT NULL UNIQUE,
            thread_id TEXT NOT NULL,
            subject TEXT NOT NULL,
            sender TEXT NOT NULL,
            recipient TEXT NOT NULL,
            date DATETIME NOT NULL,
            content TEXT NOT NULL,
            labels TEXT,
            snippet TEXT,
            timestamp INTEGER NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        """
        try execute(emailsSQL)
        print("emails table ready")
        
        try execute("CREATE INDEX IF NOT EXISTS idx_email_id ON Email(id);")
        try execute("CREATE INDEX IF NOT EXISTS idx_email_thread_id ON Email(thread_id);")
        print("created email indexes")
        
        
        let messagesSQL = """
        CREATE TABLE IF NOT EXISTS Message(
            id TEXT PRIMARY KEY,
            original_id INTEGER NOT NULL,
            text TEXT NOT NULL,
            date DATETIME NOT NULL,
            timestamp INTEGER NOT NULL,
            is_from_me BOOLEAN NOT NULL,
            is_sent BOOLEAN NOT NULL,
            service TEXT NOT NULL,
            contact TEXT NOT NULL,
            chat_name TEXT,
            chat_id TEXT,
            contact_number TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(original_id)
        );
        """
        try execute(messagesSQL)
        print("messages table ready")
        
        try execute("CREATE INDEX IF NOT EXISTS idx_message_id on Email(id);")
        try execute("CREATE INDEX IF NOT EXISTS idx_contact ON Message(contact);")
        print("created message indexes")
        
        let notesSQL = """
        CREATE TABLE IF NOT EXISTS Note(
            id TEXT PRIMARY KEY,
            original_id INTEGER NOT NULL,
            title TEXT NOT NULL,
            snippet TEXT,
            content TEXT NOT NULL,
            folder TEXT NOT NULL,
            created DATE,
            modified DATETIME NOT NULL,
            creation_timestamp REAL,
            modification_timestamp REAL NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );        
        """
        try execute(notesSQL)
        print("notes table ready")
        
        try execute("CREATE INDEX IF NOT EXISTS idx_note_id ON Note(id);")
        print("created notes indexes")
        
        let itemsSQL = """
        CREATE TABLE IF NOT EXISTS Item(
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL CHECK(type IN ('document', 'email', 'message', 'note')),
            thread_id TEXT NOT NULL,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            snippet TEXT NOT NULL,
            date DATETIME NOT NULL,
            metadata TEXT, 
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        """
        try execute(itemsSQL)
        print("items table ready")
        
        try execute("CREATE INDEX IF NOT EXISTS idx_item_id ON Item(id);")
        try execute("CREATE INDEX IF NOT EXISTS idx_item_type ON Item(type);")
        try execute("CREATE INDEX IF NOT EXISTS idx_item_thread_id ON Item(thread_id);")
        print("created items indexes")
        
        let threadsSQL = """
        CREATE TABLE IF NOT EXISTS Thread(
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL CHECK(type IN ('document', 'email', 'message', 'note')),
            thread_id TEXT NOT NULL,
            item_ids TEXT NOT NULL,
            snippet TEXT NOT NULL,
            content TEXT NOT NULL,
            created DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        """
        try execute(threadsSQL)
        print("threads table ready")
        
        try execute("CREATE INDEX IF NOT EXISTS idx_thread_id ON Thread(id);")
        try execute("CREATE INDEX IF NOT EXISTS idx_thread_type ON Thread(type);")
        print("created threads indexes")
        
        let threadChunksSQL = """
        CREATE VIRTUAL TABLE IF NOT EXISTS Chunk USING vec0(
            id TEXT PRIMARY KEY,
            thread_id TEXT NOT NULL,
            parent_ids TEXT NOT NULL,
            type TEXT NOT NULL CHECK(content_type IN ('document', 'email', 'message', 'note')),
            chunk_index INTEGER,
            startPosition INTEGER,
            endPosition INTEGER,
            +content TEXT,
            embedding float[\(embeddingDimensions)]
        );
        """
        try execute(threadChunksSQL)
        print("thread chunks table ready")
    }
    
    // would rather not deal with race conditions later
    // only necessary on writes (wal covers reads)
    private let dbQueue = DispatchQueue(label: "sqlite.serial.db")
    
    func sync<T>(_ block: () throws -> T) rethrows -> T {
        try dbQueue.sync {
            try block()
        }
    }
    
    // MARK: - Search
    
    func searchThreadChunks(
        queryEmbedding: [Float],
        limit: Int = 20,
        types: [ContentType]? = ContentType.allCases
    ) throws -> [SearchResult] {
        let contentTypes = types ?? ContentType.allCases
        // Build the “IN (?,?,…)” part dynamically
        let placeholders = contentTypes.map { _ in "?" }.joined(separator: ",")
        let sql = """
        SELECT id, thread_id, distance
        FROM Chunk
        WHERE type IN (\(placeholders))
          AND chunk_index = 0
          AND embedding MATCH vec_f32(?)
        ORDER BY distance
        LIMIT ?;
        """
        
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        
        for (i, ct) in contentTypes.enumerated() {
            guard sqlite3_bind_text(stmt, Int32(i + 1), ct.rawValue, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
                throw SQLiteError.bind(message: errorMessage)
            }
        }
        
        let blob = embeddingToBlob(queryEmbedding)
        let blobIndex = contentTypes.count + 1
        guard sqlite3_bind_blob(stmt, Int32(blobIndex), blob, Int32(blob.count), nil) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        let limitIndex = contentTypes.count + 2
        guard sqlite3_bind_int(stmt, Int32(limitIndex), Int32(limit)) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        var results = [SearchResult]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let chunkId   = String(cString: sqlite3_column_text(stmt, 0))
            let threadId  = String(cString: sqlite3_column_text(stmt, 1))
            let distance  = sqlite3_column_double(stmt, 2)
            
            let chunks = try getAllChunksByThreadId(threadId)
            guard let threadChunk = chunks.first(where: { $0.id == chunkId }) else { continue }
            
            guard let thread = try findThread(id: threadId) else { continue }
            let items = try getItemsByThreadId(threadId)
            
            results.append(
                SearchResult(
                    threadChunk: threadChunk,
                    thread: thread,
                    items: items,
                    distance: distance
                )
            )
        }
        
        return results
    }
    
    // MARK: - "Optimized" Batch Insertions:
    // (optimal bc single preparation vs per row statement prep)
    
    func insertItems(_ items: [Item]) throws -> [String] {
        return try sync {
            let sql = """
                INSERT INTO Item (id, type, thread_id, title, content, snippet, date, metadata, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            var insertedIds = [String]()
            try beginTransaction()
            defer {
                sqlite3_finalize(stmt)
            }
            guard sqlite3_prepare_v2(dbPointer, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SQLiteError.prepare(message: errorMessage)
            }
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for item in items {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                let metadataData = try JSONSerialization.data(withJSONObject: item.metadata)
                let metadataString = String(data: metadataData, encoding: .utf8) ?? "{}"
                let dateString = ISO8601DateFormatter().string(from: item.date)
                guard
                    sqlite3_bind_text(stmt, 1, item.id, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 2, item.type.rawValue, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 3, item.threadId, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 4, item.title, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 5, item.content, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 6, item.snippet, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 7, dateString, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 8, metadataString, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 9, dateString, -1, SQLITE_TRANSIENT) == SQLITE_OK
                else {
                    throw SQLiteError.bind(message: errorMessage)
                }
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw SQLiteError.step(message: errorMessage)
                }
                insertedIds.append(item.id)
            }
            try commitTransaction()
            return insertedIds
        }
    }
    
    
    func insertDocuments(_ documents: [Document]) throws -> [String] {
        return try sync {
            let sql = "INSERT INTO Document (id, title, content, created_at) VALUES (?, ?, ?, ?);"
            var stmt: OpaquePointer?
            var insertedIds = [String]()
            try beginTransaction()
            defer {
                sqlite3_finalize(stmt)
            }
            guard sqlite3_prepare_v2(dbPointer, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SQLiteError.prepare(message: errorMessage)
            }
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for doc in documents {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                guard
                    sqlite3_bind_text(stmt, 1, doc.id, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 2, doc.title, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 3, doc.content, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 4, ISO8601DateFormatter().string(from: doc.createdAt), -1, SQLITE_TRANSIENT) == SQLITE_OK
                else {
                    throw SQLiteError.bind(message: errorMessage)
                }
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw SQLiteError.step(message: errorMessage)
                }
                insertedIds.append(doc.id)
            }
            try commitTransaction()
            return insertedIds
        }
    }
    
    
    func insertEmails(_ emails: [Email]) throws -> [String] {
        return try sync {
            let sql = """
                INSERT INTO Email (id, original_id, thread_id, subject, sender, recipient, date, content, labels, snippet, timestamp, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            var insertedIds = [String]()
            try beginTransaction()
            defer {
                sqlite3_finalize(stmt)
            }
            guard sqlite3_prepare_v2(dbPointer, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SQLiteError.prepare(message: errorMessage)
            }
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for email in emails {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                let labelsJSON = try JSONSerialization.data(withJSONObject: email.labels)
                let labelsString = String(data: labelsJSON, encoding: .utf8) ?? "[]"
                guard
                    sqlite3_bind_text(stmt, 1, email.id, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 2, email.originalId, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 3, email.threadId, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 4, email.subject, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 5, email.sender, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 6, email.recipient, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 7, ISO8601DateFormatter().string(from: email.date), -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 8, email.content, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 9, labelsString, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 10, email.snippet, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_int64(stmt, 11, email.timestamp) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 12, ISO8601DateFormatter().string(from: email.createdAt), -1, SQLITE_TRANSIENT) == SQLITE_OK
                else {
                    throw SQLiteError.bind(message: errorMessage)
                }
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw SQLiteError.step(message: errorMessage)
                }
                insertedIds.append(email.id)
            }
            try commitTransaction()
            return insertedIds
        }
    }
    
    func insertNotes(_ notes: [Note]) throws -> [String] {
        return try sync {
            let sql = """
                INSERT INTO Note (id, original_id, title, snippet, content, folder, created, modified, creation_timestamp, modification_timestamp, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            var insertedIds = [String]()
            try beginTransaction()
            defer {
                sqlite3_finalize(stmt)
            }
            guard sqlite3_prepare_v2(dbPointer, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SQLiteError.prepare(message: errorMessage)
            }
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for note in notes {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                guard
                    sqlite3_bind_text(stmt, 1, note.id, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_int(stmt, 2, note.originalId) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 3, note.title, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 4, note.snippet ?? "", -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 5, note.content, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 6, note.folder, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 7, note.created.map { ISO8601DateFormatter().string(from: $0) } ?? "", -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 8, ISO8601DateFormatter().string(from: note.modified), -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_double(stmt, 9, note.creationTimestamp ?? 0) == SQLITE_OK,
                    sqlite3_bind_double(stmt, 10, note.modificationTimestamp) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 11, ISO8601DateFormatter().string(from: note.createdAt), -1, SQLITE_TRANSIENT) == SQLITE_OK
                else {
                    throw SQLiteError.bind(message: errorMessage)
                }
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw SQLiteError.step(message: errorMessage)
                }
                insertedIds.append(note.id)
            }
            try commitTransaction()
            return insertedIds
        }
    }
    
    func insertMessages(_ messages: [Message]) throws -> [String] {
        return try sync {
            let sql = """
                INSERT INTO Message (id, original_id, text, date, timestamp, is_from_me, is_sent, service, contact, chat_name, chat_id, contact_number, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            var insertedIds = [String]()
            try beginTransaction()
            defer {
                sqlite3_finalize(stmt)
            }
            guard sqlite3_prepare_v2(dbPointer, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SQLiteError.prepare(message: errorMessage)
            }
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for message in messages {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                guard
                    sqlite3_bind_text(stmt, 1, message.id, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_int(stmt, 2, message.originalId) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 3, message.text, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 4, ISO8601DateFormatter().string(from: message.date), -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_int64(stmt, 5, message.timestamp) == SQLITE_OK,
                    sqlite3_bind_int(stmt, 6, message.isFromMe ? 1 : 0) == SQLITE_OK,
                    sqlite3_bind_int(stmt, 7, message.isSent ? 1 : 0) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 8, message.service, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 9, message.contact, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 10, message.chatName ?? "", -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 11, message.chatId ?? "", -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 12, message.contactNumber ?? "", -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 13, ISO8601DateFormatter().string(from: message.createdAt), -1, SQLITE_TRANSIENT) == SQLITE_OK
                else {
                    throw SQLiteError.bind(message: errorMessage)
                }
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw SQLiteError.step(message: errorMessage)
                }
                insertedIds.append(message.id)
            }
            try commitTransaction()
            return insertedIds
        }
    }
    
    func insertThreadChunks(_ threadChunks: [ThreadChunk]) throws -> [String] {
        return try sync {
            let sql = """
                INSERT INTO Chunk (id, thread_id, parent_ids, type, content, chunk_index, startPosition, endPosition, embedding)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, vec_f32(?));
            """
            var stmt: OpaquePointer?
            var insertedIds = [String]()
            try beginTransaction()
            defer {
                sqlite3_finalize(stmt)
            }
            guard sqlite3_prepare_v2(dbPointer, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SQLiteError.prepare(message: errorMessage)
            }
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for chunk in threadChunks {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                let parentIdsJSON = try JSONSerialization.data(withJSONObject: chunk.parentIds)
                let parentIdsString = String(data: parentIdsJSON, encoding: .utf8) ?? "[]"
                let vectorBlob = embeddingToBlob(chunk.embedding)
                guard
                    sqlite3_bind_text(stmt, 1, chunk.id, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 2, chunk.threadId, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 3, parentIdsString, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 4, chunk.type.rawValue, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_text(stmt, 5, chunk.content, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                    sqlite3_bind_int(stmt, 6, Int32(chunk.chunkIndex)) == SQLITE_OK,
                    sqlite3_bind_int(stmt, 7, Int32(chunk.startPosition)) == SQLITE_OK,
                    sqlite3_bind_int(stmt, 8, Int32(chunk.endPosition)) == SQLITE_OK,
                    sqlite3_bind_blob(stmt, 9, vectorBlob, Int32(vectorBlob.count), nil) == SQLITE_OK
                else {
                    throw SQLiteError.bind(message: errorMessage)
                }
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw SQLiteError.step(message: errorMessage)
                }
                insertedIds.append(chunk.id)
            }
            try commitTransaction()
            return insertedIds
        }
    }
    
    
    // MARK: - Batch Query
    func getAllDocuments(limit: Int? = nil, offset: Int? = nil, orderBy: String? = nil) throws -> [Document] {
        var sql = "SELECT * FROM Document"
        if let orderBy = orderBy {
            sql += " ORDER BY \(orderBy)"
        }
        if let limit = limit {
            sql += " LIMIT \(limit)"
            if let offset = offset {
                sql += " OFFSET \(offset)"
            }
        }
        sql += ";"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        var results = [Document]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(extractDocument(from: stmt))
        }
        return results
    }
    
    func getAllEmails(limit: Int? = nil, offset: Int? = nil, orderBy: String? = nil) throws -> [Email] {
        var sql = "SELECT * FROM Email"
        if let orderBy = orderBy {
            sql += " ORDER BY \(orderBy)"
        }
        if let limit = limit {
            sql += " LIMIT \(limit)"
            if let offset = offset {
                sql += " OFFSET \(offset)"
            }
        }
        sql += ";"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        var results = [Email]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(try extractEmail(from: stmt))
        }
        return results
    }
    
    func getAllMessages(limit: Int? = nil, offset: Int? = nil, orderBy: String? = nil) throws -> [Message] {
        var sql = "SELECT * FROM Message"
        if let orderBy = orderBy {
            sql += " ORDER BY \(orderBy)"
        }
        if let limit = limit {
            sql += " LIMIT \(limit)"
            if let offset = offset {
                sql += " OFFSET \(offset)"
            }
        }
        sql += ";"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        var results = [Message]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(extractMessage(from: stmt))
        }
        return results
    }
    
    func getAllNotes(limit: Int? = nil, offset: Int? = nil, orderBy: String? = nil) throws -> [Note] {
        var sql = "SELECT * FROM Note"
        if let orderBy = orderBy {
            sql += " ORDER BY \(orderBy)"
        }
        if let limit = limit {
            sql += " LIMIT \(limit)"
            if let offset = offset {
                sql += " OFFSET \(offset)"
            }
        }
        sql += ";"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        var results = [Note]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(extractNote(from: stmt))
        }
        return results
    }
    
    func getAllThreads(limit: Int? = nil, offset: Int? = nil, orderBy: String? = nil) throws -> [Thread] {
        var sql = "SELECT * FROM Thread"
        if let orderBy = orderBy {
            sql += " ORDER BY \(orderBy)"
        }
        if let limit = limit {
            sql += " LIMIT \(limit)"
            if let offset = offset {
                sql += " OFFSET \(offset)"
            }
        }
        sql += ";"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        var results = [Thread]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(try extractThread(from: stmt))
        }
        return results
    }
    
    func getAllItems(limit: Int? = nil, offset: Int? = nil, orderBy: String? = nil) throws -> [Item] {
        var sql = "SELECT * FROM Item "
        if let orderBy = orderBy {
            sql += " ORDER BY \(orderBy)"
        }
        if let limit = limit {
            sql += " LIMIT \(limit)"
            if let offset = offset {
                sql += " OFFSET \(offset)"
            }
        }
        sql += ";"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        var results = [Item]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(try extractItem(from: stmt))
        }
        return results
    }
    
    func getAllChunksByThreadId(_ threadId: String) throws -> [ThreadChunk] {
        let sql = "SELECT * FROM Chunk WHERE thread_id = ?;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        
        if sqlite3_bind_text(stmt, 1, threadId, -1, SQLITE_TRANSIENT) != SQLITE_OK {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        var results = [] as [ThreadChunk]
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(try extractThreadChunk(from: stmt))
        }
        
        return results
    }
    
    func getAllChunks() throws -> [ThreadChunk] {
        let sql = "SELECT * FROM Chunk;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        var results = [] as [ThreadChunk]
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(try extractThreadChunk(from: stmt))
        }
        
        return results
    }
    
    // MARK: - Query by ID
    func getItemsByThreadId(_ threadId: String, type: String? = nil, limit: Int? = nil, offset: Int? = nil, orderBy: String? = nil) throws -> [Item] {
        print("preparing SQL with threadId: \(threadId)")
        var sql = "SELECT * FROM Item WHERE thread_id = ?"
        if let type = type {
            sql += " AND type = '\(type)'"
        }
        if let orderBy = orderBy {
            sql += " ORDER BY \(orderBy)"
        }
        if let limit = limit {
            sql += " LIMIT \(limit)"
            if let offset = offset {
                sql += " OFFSET \(offset)"
            }
        }
        sql += ";"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(stmt, 1, threadId, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        var results = [Item]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(try extractItem(from: stmt))
        }
        
        print("got \(results.count) items with threadId: \(threadId)")
        return results
    }
    
    
    func findItem(id: String) throws -> Item? {
        let sql = "SELECT * FROM Item WHERE id = ?;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return try extractItem(from: stmt)
        }
        return nil
    }
    
    func findItems(ids: [String]) throws -> [Item] {
        guard !ids.isEmpty else { return [] }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let sql = "SELECT * FROM Item WHERE id IN (\(placeholders));"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, id) in ids.enumerated() {
            guard sqlite3_bind_text(stmt, Int32(index + 1), id, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
                throw SQLiteError.bind(message: errorMessage)
            }
        }
        
        var results = [Item]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(try extractItem(from: stmt))
        }
        return results
    }
    
    func findNote(id: String) throws -> Note? {
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
    
    func findDocument(id: String) throws -> Document? {
        let sql = "SELECT * FROM Document WHERE id = ?;"
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
    
    func findEmail(id: String) throws -> Email? {
        let sql = "SELECT * FROM Email WHERE id = ?;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return try extractEmail(from: stmt)
        }
        return nil
    }
    
    func findMessage(id: String) throws -> Message? {
        let sql = "SELECT * FROM Message WHERE id = ?;"
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
    
    func findThread(id: String) throws -> Thread? {
        let sql = "SELECT * FROM Thread WHERE id = ?;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return try extractThread(from: stmt)
        }
        return nil
    }
    
    func findThreadByOriginalId(threadId: String) throws -> Thread? {
        let sql = "SELECT * FROM Thread WHERE thread_id = ?;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(stmt, 1, threadId, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return try extractThread(from: stmt)
        }
        return nil
    }
    
    // MARK: - Basic Insertion
    func insertDocument(_ document: Document) throws -> String {
        return try sync {
            let docSQL = "INSERT INTO Document (id, title, content, created_at) VALUES (?, ?, ?, ?);"
            let stmt = try prepare(docSQL)
            defer { sqlite3_finalize(stmt) }
            
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            guard sqlite3_bind_text(stmt, 1, document.id, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 2, document.title, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 3, document.content, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 4, ISO8601DateFormatter().string(from: document.createdAt), -1, SQLITE_TRANSIENT) == SQLITE_OK else {
                throw SQLiteError.bind(message: errorMessage)
            }
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SQLiteError.step(message: errorMessage)
            }
            
            return document.id
        }
    }
    
    func insertEmail(_ email: Email) throws -> String {
        return try sync {
            let sql = """
            INSERT INTO Email (id, original_id, thread_id, subject, sender, recipient, date, content, labels, snippet, timestamp, created_at) 
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }
            
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            let labelsJSON = try JSONSerialization.data(withJSONObject: email.labels)
            let labelsString = String(data: labelsJSON, encoding: .utf8) ?? "[]"
            
            guard sqlite3_bind_text(stmt, 1, email.id, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 2, email.originalId, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 3, email.threadId, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 4, email.subject, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 5, email.sender, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 6, email.recipient, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 7, ISO8601DateFormatter().string(from: email.date), -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 8, email.content, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 9, labelsString, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 10, email.snippet, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_int64(stmt, 11, email.timestamp) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 12, ISO8601DateFormatter().string(from: email.createdAt), -1, SQLITE_TRANSIENT) == SQLITE_OK else {
                throw SQLiteError.bind(message: errorMessage)
            }
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SQLiteError.step(message: errorMessage)
            }
            
            return email.id
        }
    }
    
    func insertMessage(_ message: Message) throws -> String {
        return try sync {
            let sql = """
            INSERT INTO Message (id, original_id, text, date, timestamp, is_from_me, is_sent, service, contact, chat_name, chat_id, contact_number, created_at) 
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }
            
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            
            guard sqlite3_bind_text(stmt, 1, message.id, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_int(stmt, 2, message.originalId) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 3, message.text, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 4, ISO8601DateFormatter().string(from: message.date), -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_int64(stmt, 5, message.timestamp) == SQLITE_OK,
                  sqlite3_bind_int(stmt, 6, message.isFromMe ? 1 : 0) == SQLITE_OK,
                  sqlite3_bind_int(stmt, 7, message.isSent ? 1 : 0) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 8, message.service, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 9, message.contact, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 10, message.chatName ?? "", -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 11, message.chatId ?? "", -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 12, message.contactNumber ?? "", -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 13, ISO8601DateFormatter().string(from: message.createdAt), -1, SQLITE_TRANSIENT) == SQLITE_OK else {
                throw SQLiteError.bind(message: errorMessage)
            }
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SQLiteError.step(message: errorMessage)
            }
            
            return message.id
        }
    }
    
    func insertNote(_ note: Note) throws -> String {
        return try sync {
            let sql = """
            INSERT INTO Note (id, original_id, title, snippet, content, folder, created, modified, creation_timestamp, modification_timestamp, created_at) 
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }
            
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            
            guard sqlite3_bind_text(stmt, 1, note.id, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_int(stmt, 2, note.originalId) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 3, note.title, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 4, note.snippet ?? "", -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 5, note.content, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 6, note.folder, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 7, note.created.map { ISO8601DateFormatter().string(from: $0) } ?? "", -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 8, ISO8601DateFormatter().string(from: note.modified), -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_double(stmt, 9, note.creationTimestamp ?? 0) == SQLITE_OK,
                  sqlite3_bind_double(stmt, 10, note.modificationTimestamp) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 11, ISO8601DateFormatter().string(from: note.createdAt), -1, SQLITE_TRANSIENT) == SQLITE_OK else {
                throw SQLiteError.bind(message: errorMessage)
            }
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SQLiteError.step(message: errorMessage)
            }
            
            return note.id
        }
    }
    
    func insertThread(_ thread: Thread) throws -> String {
        return try sync {
            let sql = """
            INSERT INTO Thread
            (id, type, thread_id, item_ids, snippet, content, created)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }
            
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            
            let itemIdsJSON = try JSONSerialization.data(withJSONObject: thread.itemIds)
            let itemIdsString = String(data: itemIdsJSON, encoding: .utf8) ?? "[]"
            
            
            guard sqlite3_bind_text(stmt, 1, thread.id, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 2, thread.type.rawValue, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 3, thread.threadId, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 4, itemIdsString, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 5, thread.snippet, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 6, thread.content, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 7, ISO8601DateFormatter().string(from: thread.created), -1, SQLITE_TRANSIENT) == SQLITE_OK else {
                throw SQLiteError.bind(message: errorMessage)
            }
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SQLiteError.step(message: errorMessage)
            }
            
            return thread.id
        }
    }
    
    func insertItem(_ item: Item) throws -> String {
        return try sync {
            let sql = """
                INSERT INTO Item (id, type, thread_id, title, content, snippet, date, metadata, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
                """
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }
            
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            let metadataData = try JSONSerialization.data(withJSONObject: item.metadata)
            let metadataString = String(data: metadataData, encoding: .utf8) ?? "{}"
            let dateString = ISO8601DateFormatter().string(from: item.date)
            
            guard
                sqlite3_bind_text(stmt, 1, item.id, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                sqlite3_bind_text(stmt, 2, item.type.rawValue, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                sqlite3_bind_text(stmt, 3, item.threadId, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                sqlite3_bind_text(stmt, 4, item.title, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                sqlite3_bind_text(stmt, 5, item.content, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                sqlite3_bind_text(stmt, 6, item.snippet, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                sqlite3_bind_text(stmt, 7, dateString, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                sqlite3_bind_text(stmt, 8, metadataString, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                sqlite3_bind_text(stmt, 9, dateString, -1, SQLITE_TRANSIENT) == SQLITE_OK
            else {
                throw SQLiteError.bind(message: errorMessage)
            }
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SQLiteError.step(message: errorMessage)
            }
            
            return item.id
        }
    }
    
    func insertThreadChunk(_ threadChunk: ThreadChunk) throws -> String {
        return try sync {
            let sql = """
            INSERT INTO Chunk (id, thread_id, parent_ids, type, content, chunk_index, startPosition, endPosition, embedding) 
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, vec_f32(?));
            """
            
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }
            
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            
            let parentIdsJSON = try JSONSerialization.data(withJSONObject: threadChunk.parentIds)
            let parentIdsString = String(data: parentIdsJSON, encoding: .utf8) ?? "[]"
            
            let vectorBlob = embeddingToBlob(threadChunk.embedding)
            
            guard sqlite3_bind_text(stmt, 1, threadChunk.id, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 2, threadChunk.threadId, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 3, parentIdsString, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 4, threadChunk.type.rawValue, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_text(stmt, 5, threadChunk.content, -1, SQLITE_TRANSIENT) == SQLITE_OK,
                  sqlite3_bind_int(stmt, 6, Int32(threadChunk.chunkIndex)) == SQLITE_OK,
                  sqlite3_bind_int(stmt, 7, Int32(threadChunk.startPosition)) == SQLITE_OK,
                  sqlite3_bind_int(stmt, 8, Int32(threadChunk.endPosition)) == SQLITE_OK,
                  sqlite3_bind_blob(stmt, 9, vectorBlob, Int32(vectorBlob.count), nil) == SQLITE_OK
            else {
                throw SQLiteError.bind(message: errorMessage)
            }
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SQLiteError.step(message: errorMessage)
            }
            
            return threadChunk.id
        }
    }
    
    /// convert [Float] to binary blob (4 bytes per float, little endian)
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
    
    private func blobToEmbedding(_ blob: UnsafeRawPointer?, count: Int) -> [Float] {
        guard let blob = blob else { return [] }
        var floats = [Float](repeating: 0, count: count)
        let pointer = blob.assumingMemoryBound(to: UInt8.self)
        for i in 0..<count {
            let base = pointer + (i * 4)
            let value = base.withMemoryRebound(to: UInt32.self, capacity: 1) { $0.pointee }
            floats[i] = Float(bitPattern: value)
        }
        return floats
    }
    
    
    private func extractNote(from stmt: OpaquePointer?) -> Note {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
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
        
        return Note(id: id, originalId: originalId, title: title, snippet: snippet, content: content, folder: folder, created: created.flatMap(formatter.date), modified: formatter.date(from: modified) ?? Date(timeIntervalSinceReferenceDate: modificationTimestamp), creationTimestamp: creationTimestamp, modificationTimestamp: modificationTimestamp)
    }
    
    private func extractDocument(from stmt: OpaquePointer?) -> Document {
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let title = String(cString: sqlite3_column_text(stmt, 1))
        let content = String(cString: sqlite3_column_text(stmt, 2))
        let createdAtString = String(cString: sqlite3_column_text(stmt, 3))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let createdAt = formatter.date(from: createdAtString) ?? Date()
        return Document(id: id, title: title, content: content, createdAt: createdAt)
    }
    
    private func extractEmail(from stmt: OpaquePointer?) throws -> Email {
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let originalId = String(cString: sqlite3_column_text(stmt, 1))
        let threadId = String(cString: sqlite3_column_text(stmt, 2))
        let subject = String(cString: sqlite3_column_text(stmt, 3))
        let sender = String(cString: sqlite3_column_text(stmt, 4))
        let recipient = String(cString: sqlite3_column_text(stmt, 5))
        let dateString = String(cString: sqlite3_column_text(stmt, 6))
        let content = String(cString: sqlite3_column_text(stmt, 7))
        let labelsJSON = String(cString: sqlite3_column_text(stmt, 8))
        let snippet = String(cString: sqlite3_column_text(stmt, 9))
        let timestamp = sqlite3_column_int64(stmt, 10)
        let createdAtString = String(cString: sqlite3_column_text(stmt, 11))
        
        let iso = ISO8601DateFormatter()
        guard let date = iso.date(from: dateString), let createdAt = iso.date(from: createdAtString) else {
            throw SQLiteError.step(message: "Date parsing error")
        }
        
        let labelsData = labelsJSON.data(using: .utf8) ?? Data()
        let labels = (try? JSONSerialization.jsonObject(with: labelsData) as? [String]) ?? []
        
        return Email(
            id: id,
            originalId: originalId,
            threadId: threadId,
            subject: subject,
            sender: sender,
            recipient: recipient,
            date: date,
            content: content,
            labels: labels,
            snippet: snippet,
            timestamp: timestamp,
            createdAt: createdAt
        )
    }
    
    private func extractMessage(from stmt: OpaquePointer?) -> Message {
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let originalId = sqlite3_column_int(stmt, 1)
        let text = String(cString: sqlite3_column_text(stmt, 2))
        let dateString = String(cString: sqlite3_column_text(stmt, 3))
        let timestamp = sqlite3_column_int64(stmt, 4)
        let isFromMe = sqlite3_column_int(stmt, 5) == 1
        let isSent = sqlite3_column_int(stmt, 6) == 1
        let service = String(cString: sqlite3_column_text(stmt, 7))
        let contact = String(cString: sqlite3_column_text(stmt, 8))
        let chatName = String(cString: sqlite3_column_text(stmt, 9))
        let chatId = String(cString: sqlite3_column_text(stmt, 10))
        let contactNumber = String(cString: sqlite3_column_text(stmt, 11))
        let createdAtString = String(cString: sqlite3_column_text(stmt, 12))
        
        let iso = ISO8601DateFormatter()
        let date = iso.date(from: dateString) ?? Date()
        let createdAt = iso.date(from: createdAtString) ?? Date()
        
        return Message(
            id: id,
            originalId: originalId,
            text: text,
            date: date,
            timestamp: timestamp,
            isFromMe: isFromMe,
            isSent: isSent,
            service: service,
            contact: contact,
            chatName: chatName.isEmpty ? nil : chatName,
            chatId: chatId.isEmpty ? nil : chatId,
            contactNumber: contactNumber.isEmpty ? nil : contactNumber,
            createdAt: createdAt
        )
    }
    
    private func extractThread(from stmt: OpaquePointer?) throws -> Thread {
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let typeString = String(cString: sqlite3_column_text(stmt, 1))
        let threadId = String(cString: sqlite3_column_text(stmt, 2))
        let itemIdsJSON = String(cString: sqlite3_column_text(stmt, 3))
        let snippet = String(cString: sqlite3_column_text(stmt, 4))
        let content = String(cString: sqlite3_column_text(stmt, 5))
        let createdString = String(cString: sqlite3_column_text(stmt, 6))
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let created = formatter.date(from: createdString) ?? Date()
        
        guard let type = ContentType(rawValue: typeString) else {
            throw SQLiteError.step(message: "Unknown content type: \(typeString)")
        }
        
        let data = itemIdsJSON.data(using: .utf8) ?? Data()
        let itemIds = (try JSONSerialization.jsonObject(with: data) as? [String]) ?? []
        
        return Thread(
            id: id,
            type: type,
            itemIds: itemIds,
            threadId: threadId,
            snippet: snippet,
            content: content,
            created: created
        )
    }
    
    private func extractThreadChunk(from stmt: OpaquePointer?) throws -> ThreadChunk {
        let id = String(cString: sqlite3_column_text(stmt, 0))
        
        let threadId = String(cString: sqlite3_column_text(stmt, 1))
        
        let parentIdsJSON = String(cString: sqlite3_column_text(stmt, 2))
        let parentIdsData = parentIdsJSON.data(using: .utf8) ?? Data()
        let parentIds = (try? JSONSerialization.jsonObject(with: parentIdsData) as? [String]) ?? []
        
        let typeString = String(cString: sqlite3_column_text(stmt, 3))
        guard let type = ContentType(rawValue: typeString) else {
            throw SQLiteError.step(message: "Unknown content type: \(typeString)")
        }
        
        let chunkIndex = Int(sqlite3_column_int(stmt, 4))
        
        let startPosition = Int(sqlite3_column_int(stmt, 5))
        
        let endPosition = Int(sqlite3_column_int(stmt, 6))
        
        let content = String(cString: sqlite3_column_text(stmt, 7))
        
        let embeddingCount = self.embeddingDimensions
        let blobPointer = sqlite3_column_blob(stmt, 8)
        let blobSize = Int(sqlite3_column_bytes(stmt, 8))
        let embedding: [Float]
        if let blobPointer = blobPointer, blobSize == embeddingCount * 4 {
            embedding = blobToEmbedding(blobPointer, count: embeddingCount)
        } else {
            embedding = []
        }
        
        return ThreadChunk(
            id: id,
            threadId: threadId,
            parentIds: parentIds,
            type: type,
            content: content,
            embedding: embedding,
            chunkIndex: chunkIndex,
            startPosition: startPosition,
            endPosition: endPosition
        )
    }
    
    private func extractItem(from stmt: OpaquePointer?) throws -> Item {
        guard let stmt = stmt else { throw SQLiteError.step(message: "Invalid statement") }
        
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let typeRaw = String(cString: sqlite3_column_text(stmt, 1))
        let threadId = String(cString: sqlite3_column_text(stmt, 2))
        let title = String(cString: sqlite3_column_text(stmt, 3))
        let content = String(cString: sqlite3_column_text(stmt, 4))
        let snippet = String(cString: sqlite3_column_text(stmt, 5))
        let dateString = String(cString: sqlite3_column_text(stmt, 6))
        let metadataJSON = String(cString: sqlite3_column_text(stmt, 7))
        
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: dateString) ?? Date()
        
        let metadataData = metadataJSON.data(using: .utf8) ?? Data()
        let metadata = (try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any]) ?? [:]
        
        guard let type = ContentType(rawValue: typeRaw) else {
            throw SQLiteError.step(message: "Unknown content type: \(typeRaw)")
        }
        
        return Item(
            id: id,
            type: type,
            title: title,
            content: content,
            embeddableText: content,
            snippet: snippet,
            date: date,
            threadId: threadId,
            metadata: metadata
        )
    }
    
    
    
    // MARK: - Private Helpers
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
    
    private func beginTransaction() throws {
        try execute("BEGIN TRANSACTION;")
    }
    
    private func commitTransaction() throws {
        try execute("COMMIT;")
    }
    
    func clearAllData() throws {
        try execute("DELETE FROM Document;")
        try execute("DELETE FROM Note;")
        try execute("DELETE FROM Email;")
        try execute("DELETE FROM Thread;")
        try execute("DELETE FROM Chunk;")
        try execute("DELETE FROM Item;")
    }
}


