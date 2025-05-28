//
//  constants.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 5/25/25.
//
import Foundation
import Combine

/*
 FileManager.default.url(...) tries to get the path to the user's document directory.

 if that works, it appends "knowledge_base.sqlite" to it (i.e., creates a path like /Users/you/Documents/knowledge_base.sqlite)

 .path extracts the string path from the URL object.

 if any of that fails, it falls back to ":memory:", which is the SQLite special path for an in-memory db (non-persistent).
 
 for future could be useful to have some intermediate btwn in memory vs permanent, perhaps cache file or similar
 */
let defaultDBPath: String = {
    if let url = try? FileManager.default
        .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        .appendingPathComponent("knowledge_base.sqlite") {
        return url.path
    }
    return ":memory:"
}()

/// schema version to detect breaking changes
let schemaVersion = 2
// 2. bumped for new document tables
let databaseVersionKey = "dbSchemaVersion"

