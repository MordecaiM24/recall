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
        // create documents table
        let documentsSQL = """
        CREATE TABLE IF NOT EXISTS Document(
            Id INTEGER PRIMARY KEY AUTOINCREMENT,
            Title TEXT NOT NULL,
            Content TEXT NOT NULL,
            CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        """
        try execute(documentsSQL)
        
        // create vector table for embeddings
        let vectorSQL = "CREATE VIRTUAL TABLE IF NOT EXISTS DocumentEmbedding USING vec0(embedding float[\(embeddingDimensions)]);"
        try execute(vectorSQL)
        
        // legacy contact table
        let contactSQL = """
        CREATE TABLE IF NOT EXISTS Contact(
            Id INTEGER PRIMARY KEY AUTOINCREMENT,
            Name TEXT NOT NULL
        );
        """
        try execute(contactSQL)
    }
    
    // MARK: - Document Operations
    
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
        
        // insert embedding with same rowid using vec_f32()
        try insertEmbedding(rowid: Int32(documentId), embedding: embedding)
        
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
        // first get matching rowids and distances
        let vectorSQL = "SELECT rowid, distance FROM DocumentEmbedding WHERE embedding MATCH vec_f32(?) ORDER BY distance LIMIT ?;"
        
        let stmt = try prepare(vectorSQL)
        defer { sqlite3_finalize(stmt) }
        
        let vectorBlob = embeddingToBlob(queryEmbedding)
        
        guard sqlite3_bind_blob(stmt, 1, vectorBlob, Int32(vectorBlob.count), nil) == SQLITE_OK,
              sqlite3_bind_int(stmt, 2, Int32(limit)) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        
        var results = [SearchResult]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowid = sqlite3_column_int(stmt, 0)
            let distance = sqlite3_column_double(stmt, 1)
            
            // fetch the actual document by id
            if let document = try findDocument(id: rowid) {
                results.append(SearchResult(document: document, distance: distance))
            }
        }
        
        print("total results: \(results.count)")
        return results
    }
    
    // MARK: - Private Helpers
    
    private func insertEmbedding(rowid: Int32, embedding: [Float]) throws {
        // use vec_f32() to convert blob to proper vector
        let sql = "INSERT INTO DocumentEmbedding(rowid, embedding) VALUES (?, vec_f32(?));"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        
        let vectorBlob = embeddingToBlob(embedding)
        
        guard sqlite3_bind_int(stmt, 1, rowid) == SQLITE_OK,
              sqlite3_bind_blob(stmt, 2, vectorBlob, Int32(vectorBlob.count), nil) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteError.step(message: errorMessage)
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
    
    private func extractDocument(from stmt: OpaquePointer?) -> Document {
        let id = sqlite3_column_int(stmt, 0)
        let title = String(cString: sqlite3_column_text(stmt, 1))
        let content = String(cString: sqlite3_column_text(stmt, 2))
        
        // parse date
        let dateString = String(cString: sqlite3_column_text(stmt, 3)) 
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: dateString) ?? Date()
        
        return Document(id: id, title: title, content: content, createdAt: date)
    }
}
