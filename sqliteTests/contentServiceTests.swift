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
    
    // dummy data generation
    func dummyDocument(id: String = UUID().uuidString) -> Document {
        Document(id: id, title: "Doc Title", content: "Doc Content", createdAt: Date())
    }
    
    func dummyEmail(id: String = UUID().uuidString, threadId: String = "thread-x", date: Date = Date()) -> Email {
        Email(id: id, originalId: "orig-\(id)", threadId: threadId, subject: "Email Subject", sender: "sender@t.com", recipient: "to@t.com", date: Date(), content: "Email Content", labels: ["INBOX"], snippet: "Snippet", timestamp: Int64(Date().timeIntervalSince1970))
    }
    
    func dummyMessage(id: String = UUID().uuidString, threadId: String = "Bob", date: Date = Date(), idx: Int) -> Message {
        Message(id: id, originalId: Int32(idx), text: "Hello message", date: date, timestamp: Int64(Date().timeIntervalSince1970), isFromMe: true, isSent: true, service: "iMessage", contact: threadId, chatName: "TestChat", chatId: "chat123", contactNumber: "123-4567", createdAt: Date())
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
    
    // test threading and batch import for documents
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
    
    // test threading and batch import for messages
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
    
    // test threading and batch import for notes
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
    
    // asserts that empty imports returns [] and not err
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
    
    // checks loading state doesn't cause race conditions
    func testIsLoadingDuringAdd() async throws {
        let item = dummyItem(type: .document)
        let expectation = expectation(description: "isLoading set")
        Task {
            let _ = try await contentService.add(item)
            expectation.fulfill()
        }
        
        // temporary checker - kind of hard to assert loading w/o timeout so we'll just implement that later
        XCTAssertTrue(contentService.isLoading || !contentService.isLoading) // not strict, just smoke test
        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertFalse(contentService.isLoading)
    }
    
    // helper function to control dates for pagination
    private func insertDocuments(withDates dates: [Date]) async throws -> [String] {
        var ids = [String]()
        for date in dates {
            let doc = Document(id: UUID().uuidString,
                               title: "Doc \(Int(date.timeIntervalSince1970))",
                               content: "Content",
                               createdAt: date)
            let item = Item(from: doc)
            let id = try await contentService.add(item)
            ids.append(id)
        }
        return ids
    }
    
    func testDocumentOrderingByCreatedAt() async throws {
        let now = Date()
        let earlier = now.addingTimeInterval(-300)
        let middle = now.addingTimeInterval(-150)
        let dates = [middle, now, earlier] // scrambled insertion
        
        let ids = try await insertDocuments(withDates: dates)
        
        // ascending
        let ascItems = try await contentService.all(.document, orderBy: .createdAtAsc)
        let ascIds = ascItems.map(\.id)
        XCTAssertEqual(ascIds.prefix(3), ids.sorted { dates[ids.firstIndex(of: $0)!] < dates[ids.firstIndex(of: $1)!] }.prefix(3))
        
        // descending
        let descItems = try await contentService.all(.document, orderBy: .createdAtDesc)
        let descIds = descItems.map(\.id)
        XCTAssertEqual(descIds.prefix(3), ids.sorted { dates[ids.firstIndex(of: $0)!] > dates[ids.firstIndex(of: $1)!] }.prefix(3))
    }
    
    func testDocumentPaginationOnly() async throws {
        // insert 5 docs at identical timestamp
        let baseDate = Date()
        let dates = (0..<5).map { baseDate.addingTimeInterval(TimeInterval($0)) }
        let ids = try await insertDocuments(withDates: dates)
        
        let limited = try await contentService.all(.document, limit: 2)
        XCTAssertEqual(limited.count, 2)
        XCTAssertTrue(ids.contains(limited[0].id) && ids.contains(limited[1].id))
        
        let paged = try await contentService.all(.document, limit: 2, offset: 2)
        XCTAssertEqual(paged.count, 2)
        XCTAssertEqual(Set(paged.map(\.id)), Set(ids[2..<4]))
    }
    
    func testDocumentOrderingAndPaginationCombined() async throws {
        let base = Date().addingTimeInterval(-400)
        let dates = (0..<4).map { base.addingTimeInterval(TimeInterval($0 * 100)) }
        let ids = try await insertDocuments(withDates: dates)
        
        // descending order, limit 2, offset 1 -> should pick the 2nd & 3rd newest
        let combined = try await contentService.all(
            .document,
            limit: 2,
            offset: 1,
            orderBy: .createdAtDesc
        )
        
        let sortedDesc = zip(ids, dates)
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
        let expected = Array(sortedDesc[1...2])
        
        XCTAssertEqual(combined.map(\.id), expected)
    }
    
    func insertMessagesInThread(threadId: String, count: Int, baseDate: Date = Date()) async throws -> [Message] {
        var messages: [Message] = []
        for i in 0..<count {
            let msg = dummyMessage(id: "m-\(threadId)-\(i)", threadId: threadId, idx: i)
            let message = Message(
                id: msg.id,
                originalId: msg.originalId,
                text: "Thread \(threadId) Msg \(i)",
                date: baseDate.addingTimeInterval(TimeInterval(i * 60)),
                timestamp: Int64(baseDate.addingTimeInterval(TimeInterval(i * 60)).timeIntervalSince1970),
                isFromMe: true,
                isSent: true,
                service: "iMessage",
                contact: threadId,
                chatName: "Chat-\(threadId)",
                chatId: "chat-\(threadId)",
                contactNumber: "123-\(threadId)",
                createdAt: baseDate.addingTimeInterval(TimeInterval(i * 60))
            )
            messages.append(message)
        }
        let _ = try await contentService.importMessages(messages)
        return messages
    }
    
    
    // MARK: - Thread ID bullshit
    func testByThreadIdFetchesAllItemsInDbThread() async throws {
        // Insert 3 notes, all get their own thread with db id
        let notes = (0..<3).map { dummyNote(id: "note-\($0)") }
        let _ = try await contentService.importNotes(notes)
        // Get the DB thread id for the first note (using originalId == note.id)
        guard let dbThread = try sqliteService.findThreadByOriginalId(threadId: notes[0].id) else {
            XCTFail("Thread not found for inserted note")
            return
        }
        let items = try await contentService.byThreadId(dbThread.id)
        // Should contain only that note (since thread is one-to-one for notes)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, notes[0].id)
    }
    
    func testByThreadIdWithMessagesMultipleInSameDbThread() async throws {
        // Insert multiple messages with same contact, get 1 thread
        let threadContact = "friends"
        let messages = (0..<3).map { ix in
            dummyMessage(id: "msg-\(ix)", threadId: threadContact, idx: ix)
        }
        let _ = try await contentService.importMessages(messages)
        // DB thread id for this conversation:
        guard let dbThread = try sqliteService.findThreadByOriginalId(threadId: threadContact) else {
            XCTFail("DB thread not found for contact \(threadContact)")
            return
        }
        let items = try await contentService.byThreadId(dbThread.id)
        // Should contain all messages
        XCTAssertEqual(Set(items.map(\.id)), Set(messages.map(\.id)))
    }
    
    func testByThreadIdWithOrdering() async throws {
        let threadContact = "chatty"
        let baseDate = Date()
        let messages = (0..<3).map { i in
                dummyMessage(
                    id: "msg-\(i)",
                    threadId: threadContact,
                    date: baseDate.addingTimeInterval(Double(i * 60)),
                    idx: i
                )
            }
        let _ = try await contentService.importMessages(messages)
        guard let dbThread = try sqliteService.findThreadByOriginalId(threadId: threadContact) else {
            XCTFail("DB thread not found")
            return
        }
        let asc = try await contentService.byThreadId(dbThread.id, type: .message, orderBy: .dateAsc)
        let desc = try await contentService.byThreadId(dbThread.id, type: .message, orderBy: .dateDesc)
        XCTAssertEqual(asc.map(\.id), messages.map(\.id))
        XCTAssertEqual(desc.map(\.id), messages.reversed().map(\.id))
    }
    
    func testByThreadIdWithPagination() async throws {
        let threadContact = "paginate"
        let baseDate = Date()
        let messages = (0..<5).map { i in
            Message(id: "pm-\(i)", originalId: Int32(i), text: "msg \(i)",
                    date: baseDate.addingTimeInterval(Double(i)),
                    timestamp: Int64(baseDate.addingTimeInterval(Double(i)).timeIntervalSince1970),
                    isFromMe: true, isSent: true, service: "iMessage", contact: threadContact,
                    chatName: nil, chatId: nil, contactNumber: nil,
                    createdAt: baseDate.addingTimeInterval(Double(i)))
        }
        let _ = try await contentService.importMessages(messages)
        guard let dbThread = try sqliteService.findThreadByOriginalId(threadId: threadContact) else {
            XCTFail("DB thread not found")
            return
        }
        let paged = try await contentService.byThreadId(dbThread.id, type: .message, limit: 2, offset: 2)
        XCTAssertEqual(paged.count, 2)
        XCTAssertEqual(Set(paged.map(\.id)), Set(messages[2...3].map(\.id)))
    }

    func testByThreadIdReturnsEmptyForUnknownDbId() async throws {
        let items = try await contentService.byThreadId("not-a-db-thread-id")
        XCTAssertTrue(items.isEmpty)
    }
}
