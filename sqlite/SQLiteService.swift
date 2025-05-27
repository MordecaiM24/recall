//
//  SQLiteService.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 5/25/25.
//
import Foundation
import SQLite3

// ensure sqlite_vec.h is in your bridging header to expose sqlite3_vec_init and sqlite3_api

enum SQLiteError: Error {
    case openDatabase(message: String)
    case prepare(message: String)
    case step(message: String)
    case bind(message: String)
}

final class SQLiteService {
    private let dbPointer: OpaquePointer?

    init(path: String = ephemeralDBPath) throws {
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

    func insertContact(name: String) throws {
        let sql = "INSERT INTO Contact (Name) VALUES (?);"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw SQLiteError.bind(message: errorMessage)
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteError.step(message: errorMessage)
        }
    }

    func findContacts() throws -> [Contact] {
        let sql = "SELECT Id, Name FROM Contact;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        var rows = [Contact]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int(stmt, 0)
            guard let text = sqlite3_column_text(stmt, 1) else { continue }
            let name = String(cString: text)
            rows.append(Contact(id: id, name: name))
        }
        return rows
    }

}

