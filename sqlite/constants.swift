//
//  constants.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 5/25/25.
//
import Foundation

/// path to ephemeral sqlite file
let ephemeralDBPath: String = {
    if let url = try? FileManager.default
        .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        .appendingPathComponent("ephemeral.sqlite") {
        return url.path
    }
    return ":memory:"
}()

/// schema version to detect breaking changes
let schemaVersion = 1
let databaseVersionKey = "dbSchemaVersion"
