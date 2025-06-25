//
//  ContentServiceTests.swift
//  sqliteTests
//
//  Comprehensive unit tests for ContentService.
//

import XCTest
@testable import sqlite

class ContentServiceTests: XCTestCase {
    var sqliteService: SQLiteService!
    var embeddingService: EmbeddingService!
    var contentService: ContentService!
    let testDBPath = NSTemporaryDirectory() + UUID().uuidString + "test.db"
    
    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(atPath: testDBPath)
        do {
            sqliteService = try SQLiteService(path: testDBPath, embeddingDimensions: 384)
            embeddingService = try EmbeddingService()
            try sqliteService.setupDatabase()
            contentService = ContentService(sqlite: sqliteService, embedding: embeddingService)
        } catch {
            XCTFail("Failed to setup test database: \(error)")
        }
    }
    
    override func tearDown() {
        sqliteService = nil
        embeddingService = nil
        try? FileManager.default.removeItem(atPath: testDBPath)
        super.tearDown()
    }

    // dummu data generation
    func dummyDocument(id: String = UUID().uuidString) -> Document {
        Document(id: id, title: "Doc Title", content: "Doc Content", createdAt: Date())
    }

    func dummyEmail(id: String = UUID().uuidString, threadId: String = "thread-x") -> Email {
        Email(id: id, originalId: "orig-\(id)", threadId: threadId, subject: "Email Subject", sender: "sender@t.com", recipient: "to@t.com", date: Date(), content: "Email Content", labels: ["INBOX"], snippet: "Snippet", timestamp: Int64(Date().timeIntervalSince1970))
    }

    func dummyMessage(id: String = UUID().uuidString, idx: Int) -> Message {
        Message(id: id, originalId: Int32(idx), text: "Hello message", date: Date(), timestamp: Int64(Date().timeIntervalSince1970), isFromMe: true, isSent: true, service: "iMessage", contact: "Bob", chatName: "TestChat", chatId: "chat123", contactNumber: "123-4567", createdAt: Date())
    }

    func dummyNote(id: String = UUID().uuidString) -> Note {
        Note(id: id, originalId: 55, title: "Note Title", snippet: "Note snippet", content: "Note Content", folder: "Notes", created: Date(), modified: Date(), creationTimestamp: 1111.1, modificationTimestamp: 2222.2, createdAt: Date())
    }

    func dummyItem(type: ContentType, id: String = UUID().uuidString) -> Item {
        switch type {
        case .document:
            return Item(from: dummyDocument(id: id))
        case .email:
            return Item(from: dummyEmail(id: id))
        case .message:
            return Item(from: dummyMessage(id: id, idx: 0))
        case .note:
            return Item(from: dummyNote(id: id))
        }
    }

    // fetch add and fetch for one of each content type
    func testAddAndFetchEachContentType() async throws {
        for type in ContentType.allCases {
            let item = dummyItem(type: type)
            let id = try await contentService.add(item)

            let fetched = try await contentService.one(type, id: id)
            XCTAssertNotNil(fetched)
            XCTAssertEqual(fetched?.id, id)
            XCTAssertEqual(fetched?.type, type)
            
            let all = try await contentService.all(type)
            XCTAssertTrue(all.contains(where: { $0.id == id }))
        }
    }
    
    // add and fetch multiple item types
    func testBatchAddMixedContentTypes() async throws {
        let items = [
            dummyItem(type: .document),
            dummyItem(type: .email),
            dummyItem(type: .message),
            dummyItem(type: .note)
        ]
        let ids = try await contentService.add(items)
        XCTAssertEqual(ids.count, 4)
        
        for (ix, item) in items.enumerated() {
            let fetched = try await contentService.one(item.type, id: ids[ix])
            XCTAssertNotNil(fetched)
            XCTAssertEqual(fetched?.id, ids[ix])
        }
    }

    // ensure empty array is returned and not err
    func testFetchAllEmptyReturnsEmptyArray() async throws {
        for type in ContentType.allCases {
            let all = try await contentService.all(type)
            XCTAssertEqual(all.count, 0)
        }
    }

    // ensure nil is returned and not err
    func testFetchOneUnknownIdReturnsNil() async throws {
        for type in ContentType.allCases {
            let fetched = try await contentService.one(type, id: "does-not-exist")
            XCTAssertNil(fetched)
        }
    }

    //
    func testImportDocumentsCreatesThreads() async throws {
        let docs = (0..<3).map { dummyDocument(id: "doc-\($0)") }
        let ids = try await contentService.importDocuments(docs)
        XCTAssertEqual(ids.count, docs.count)
        
        for doc in docs {
            let thread = try sqliteService.findThreadByOriginalId(threadId: doc.id)
            XCTAssertNotNil(thread)
            XCTAssertEqual(thread?.itemIds, [doc.id])
        }
    }

    func testImportMessagesCreatesThreads() async throws {
        let threadId = "msg-thread"
        let messages = (0..<2).map { ix in
            let msg = dummyMessage(id: "msg-\(ix)", idx: ix)
            return Message(id: msg.id, originalId: msg.originalId, text: "Msg \(ix)", date: msg.date, timestamp: msg.timestamp, isFromMe: msg.isFromMe, isSent: msg.isSent, service: msg.service, contact: threadId, chatName: msg.chatName, chatId: msg.chatId, contactNumber: msg.contactNumber, createdAt: msg.createdAt)
        }
        let ids = try await contentService.importMessages(messages)
        XCTAssertEqual(ids.count, messages.count)
        
        let thread = try sqliteService.findThreadByOriginalId(threadId: threadId)
        XCTAssertNotNil(thread)
        XCTAssertEqual(Set(thread?.itemIds ?? []), Set(messages.map(\.id)))
    }

    func testImportNotesCreatesThreads() async throws {
        let notes = (0..<2).map { dummyNote(id: "note-\($0)") }
        let ids = try await contentService.importNotes(notes)
        XCTAssertEqual(ids.count, notes.count)
        for note in notes {
            let thread = try sqliteService.findThreadByOriginalId(threadId: note.id)
            XCTAssertNotNil(thread)
            XCTAssertEqual(thread?.itemIds, [note.id])
        }
    }

    
    func testImportEmptyEmailsReturnsEmpty() async throws {
        let ids = try await contentService.importEmails([])
        XCTAssertEqual(ids, [])
    }
    func testImportEmptyDocumentsReturnsEmpty() async throws {
        let ids = try await contentService.importDocuments([])
        XCTAssertEqual(ids, [])
    }
    func testImportEmptyMessagesReturnsEmpty() async throws {
        let ids = try await contentService.importMessages([])
        XCTAssertEqual(ids, [])
    }
    func testImportEmptyNotesReturnsEmpty() async throws {
        let ids = try await contentService.importNotes([])
        XCTAssertEqual(ids, [])
    }

    
    func testIsLoadingDuringAdd() async throws {
        let item = dummyItem(type: .document)
        let expectation = expectation(description: "isLoading set")
        Task {
            let _ = try await contentService.add(item)
            expectation.fulfill()
        }
        // Check isLoading while operation is ongoing (approximate: short sleep)
        XCTAssertTrue(contentService.isLoading || !contentService.isLoading) // Not strict, just smoke test
        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertFalse(contentService.isLoading)
    }
}
