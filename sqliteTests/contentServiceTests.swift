//
//  contentServiceTests.swift
//  sqliteTests
//
//  Created by Mordecai Mengesteab on 6/25/25.
//

import XCTest
@testable import sqlite

import Foundation


class ContentServiceTests: XCTestCase {
    var sqliteService: SQLiteService!
    var embeddingService: EmbeddingService!
    var contentService: ContentService!
    let testDBPath = NSTemporaryDirectory() + UUID().uuidString + "test.db"
    
    override func setUp() {
        super.setUp()
        
        // clean up any existing test db
        try? FileManager.default.removeItem(atPath: testDBPath)
        
        do {
            sqliteService = try SQLiteService(path: testDBPath, embeddingDimensions: 384)
            embeddingService = try EmbeddingService()
            try sqliteService.setupDatabase()
            
            contentService = ContentService(sqlite: sqliteService, embedding: embeddingService)
            
        } catch {
            XCTFail("failed to setup test database: \(error)")
        }
    }
    
    override func tearDown() {
        sqliteService = nil
        embeddingService = nil
        try? FileManager.default.removeItem(atPath: testDBPath)
        super.tearDown()
    }
    
    func testDatabaseSetup() {
        // if we got here without crashing, setup worked
        XCTAssertNotNil(sqliteService)
        XCTAssertNotNil(contentService)
        print("database setup test passed")
    }
    
    func testEmailImportCreatesThreadAndChunks() async throws {
        print("importing emails")
        let email = Email(
            id: "email-1",
            originalId: "orig-1",
            threadId: "thread-abc",
            subject: "hello",
            sender: "me",
            recipient: "you",
            date: Date(),
            content: "This is a test email about the cosmos and AI.",
            labels: ["inbox"],
            snippet: "test email",
            timestamp: Int64(Date().timeIntervalSince1970)
        )
        
        XCTAssertNotNil(contentService)
        
        let ids = try await contentService.importEmails([email])
        print(ids)
        XCTAssertEqual(ids.count, 1)
        
        let fetchedEmail = try sqliteService.findEmail(id: ids[0])
        print(fetchedEmail)
        
        let thread = try sqliteService.findThreadByOriginalId(threadId: "thread-abc")
        XCTAssertNotNil(thread)
        XCTAssertEqual(thread?.itemIds, ["email-1"])
        
        let chunks = try sqliteService.getAllChunksByThreadId("thread-abc")
        XCTAssertGreaterThan(chunks.count, 0)
    }
}
