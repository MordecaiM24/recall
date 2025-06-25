//
//  sqliteServiceTests.swift
//  sqliteTests
//
//  Created by Mordecai Mengesteab on 6/24/25.
//

import XCTest
@testable import sqlite

import Foundation

class SQLiteServiceTests: XCTestCase {
    
    var sqliteService: SQLiteService!
    var embeddingService: EmbeddingService!
    let testDBPath = NSTemporaryDirectory() + "test.db"
    
    override func setUp() {
        super.setUp()
        
        // clean up any existing test db
        try? FileManager.default.removeItem(atPath: testDBPath)
        
        do {
            sqliteService = try SQLiteService(path: testDBPath, embeddingDimensions: 384)
            embeddingService = try EmbeddingService()
            try sqliteService.setupDatabase()
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
    
    // MARK: - Database Setup Tests
    
    func testDatabaseSetup() {
        // if we got here without crashing, setup worked
        XCTAssertNotNil(sqliteService)
        print("database setup test passed")
    }
    
    // MARK: - Basic CRUD Tests
    
    func testDocumentCRUD() async throws {
        let id = "test-uuid"
        let title = "test document"
        let content = "this is some test content for vector search"
        let date = Date(timeIntervalSinceNow: 0)
        
        let doc = Document(id: id, title: title, content: content, createdAt: date)
        
        let documentId = try sqliteService.insertDocument(doc)
        XCTAssertFalse(documentId.isEmpty, "document id should not be empty")
        
        let fetchedDoc = try sqliteService.findDocument(id: documentId)
        XCTAssertNotNil(fetchedDoc, "should be able to fetch inserted document")
        XCTAssertEqual(fetchedDoc?.title, title)
        XCTAssertEqual(fetchedDoc?.content, content)
        
        let allDocs = try sqliteService.getAllDocuments()
        XCTAssertGreaterThanOrEqual(allDocs.count, 1, "should have at least one document")
    }
    
    func testEmailCRUD() async throws {
        let id = "test-uuid"
        let originalId = "original-test-uuid"
        let threadId = "thread-test-uuid"
        let subject = "test email subject"
        let sender = "tester <test@example.com>"
        let recipient = "recipient <recipient@example.com>"
        let date = Date(timeIntervalSinceNow: 0)
        let content = "this is some test email content for vector search"
        let labels = ["INBOX"]
        let snippet = "this is ..."
        let timestamp = Int64(date.timeIntervalSince(Date(timeIntervalSince1970: 978307200)))
        
        let email = Email(id: id, originalId: originalId, threadId: threadId, subject: subject, sender: sender, recipient: recipient, date: date, content: content, labels: labels, snippet: snippet, timestamp: timestamp)
        
        let emailId = try sqliteService.insertEmail(email)
        XCTAssertFalse(emailId.isEmpty, "email id shouldn't be empty")
        
        let fetched = try sqliteService.findEmail(id: emailId)
        XCTAssertNotNil(fetched, "findEmail should return the inserted email")
        XCTAssertEqual(fetched?.subject, subject)
        XCTAssertEqual(fetched?.senderName, "tester")
        XCTAssertTrue(fetched?.isInbox == true)
        
        
        let allEmails = try sqliteService.getAllEmails()
        XCTAssertGreaterThanOrEqual(allEmails.count, 1, "getAllEmails should include our new email")
        
    }
    
    func testNoteCRUD() async throws {
        let note = Note(
            id:                  "note-1",
            originalId:          42,
            title:               "Shopping List",
            snippet:             "Milk, Bread, …",
            content:             "Milk\nBread\nEggs",
            folder:              "Personal",
            created:             Date(timeIntervalSince1970: 1_000_000),
            modified:            Date(),
            creationTimestamp:   1_000_000,
            modificationTimestamp: Date().timeIntervalSince1970
        )
        
        let noteId = try sqliteService.insertNote(note)
        XCTAssertFalse(noteId.isEmpty)
        
        let fetched = try sqliteService.findNote(id: noteId)
        XCTAssertEqual(fetched?.title, note.title)
        XCTAssertEqual(fetched?.preview, note.snippet)
        
        let all = try sqliteService.getAllNotes()
        XCTAssertGreaterThanOrEqual(all.count, 1)
    }
    
    func testMessageCRUD() async throws {
        let msg = Message(
            id:               "msg-1",
            originalId:       1001,
            text:             "Hey, are we still on for lunch?",
            date:             Date(),
            timestamp:        Int64(Date().timeIntervalSince1970),
            isFromMe:         true,
            isSent:           true,
            service:          "iMessage",
            contact:          "Alice",
            chatName:         "Group Chat",
            chatId:           "chat-xyz",
            contactNumber:    "+15551234567"
        )
        
        // INSERT
        let msgId = try sqliteService.insertMessage(msg)
        XCTAssertFalse(msgId.isEmpty)
        
        // FETCH
        let fetched = try sqliteService.findMessage(id: msgId)
        XCTAssertEqual(fetched?.text, msg.text)
        XCTAssertEqual(fetched?.serviceIcon, "💬")
        
        // FETCH ALL
        let all = try sqliteService.getAllMessages()
        XCTAssertGreaterThanOrEqual(all.count, 1)
    }
    
    func testThreadCRUD() async throws {
        let thread = Thread(id: "test-uuid", type: ContentType.document, itemIds: ["test-1", "test-2"], threadId: "thread-uuid", snippet: "snippet", content: "asdf \n----\n qwerty", created: Date(timeIntervalSinceNow: 0))
        
        let id = try sqliteService.insertThread(thread)
        XCTAssertFalse(id.isEmpty)
        
        let fetched = try sqliteService.findThread(id: id)
        XCTAssertEqual(fetched?.id, id)
        XCTAssertEqual(fetched?.id, thread.id)
        
        let _ = try sqliteService.findThreadByOriginalId(threadId: thread.threadId)
        XCTAssertEqual(fetched?.threadId, thread.threadId)
        
        let allThreads = try sqliteService.getAllThreads()
        XCTAssertGreaterThanOrEqual(allThreads.count, 1)
        XCTAssertEqual(allThreads[0].id, id)
    }
    
    func testThreadChunkCRUDAndGetByThreadId() async throws {
        // Create two thread ids
        let threadId1 = "thread-test-1"
        let threadId2 = "thread-test-2"
        let parentIds = ["parent-1", "parent-2"]
        let type = ContentType.document
        let embedding = Array(repeating: Float(0.1), count: 384)
        
        // Create three ThreadChunk instances
        let chunk1 = ThreadChunk(
            id: UUID().uuidString,
            threadId: threadId1,
            parentIds: parentIds,
            type: type,
            content: "First chunk, thread 1",
            embedding: embedding,
            chunkIndex: 0,
            startPosition: 0,
            endPosition: 10
        )
        let chunk2 = ThreadChunk(
            id: UUID().uuidString,
            threadId: threadId1,
            parentIds: parentIds,
            type: type,
            content: "Second chunk, thread 1",
            embedding: embedding,
            chunkIndex: 1,
            startPosition: 11,
            endPosition: 20
        )
        let chunk3 = ThreadChunk(
            id: UUID().uuidString,
            threadId: threadId2,
            parentIds: parentIds,
            type: type,
            content: "Only chunk, thread 2",
            embedding: embedding,
            chunkIndex: 0,
            startPosition: 0,
            endPosition: 15
        )
        
        // Insert them
        let chunk1Id = try sqliteService.insertThreadChunk(chunk1)
        let chunk2Id = try sqliteService.insertThreadChunk(chunk2)
        let chunk3Id = try sqliteService.insertThreadChunk(chunk3)
        XCTAssertFalse(chunk1Id.isEmpty)
        XCTAssertFalse(chunk2Id.isEmpty)
        XCTAssertFalse(chunk3Id.isEmpty)
        
        // Fetch all for threadId1
        let thread1Chunks = try sqliteService.getAllChunksByThreadId(threadId1)
        XCTAssertEqual(thread1Chunks.count, 2, "Should fetch exactly 2 chunks for threadId1")
        let thread1Ids = thread1Chunks.map { $0.id }
        XCTAssertTrue(thread1Ids.contains(chunk1.id))
        XCTAssertTrue(thread1Ids.contains(chunk2.id))
        XCTAssertFalse(thread1Ids.contains(chunk3.id))
        
        // Verify fields for one of them
        if let first = thread1Chunks.first(where: { $0.id == chunk1.id }) {
            XCTAssertEqual(first.content, chunk1.content)
            XCTAssertEqual(first.chunkIndex, chunk1.chunkIndex)
            XCTAssertEqual(first.threadId, chunk1.threadId)
            XCTAssertEqual(first.embedding.count, embedding.count)
            XCTAssertEqual(first.embedding[0], 0.1, accuracy: 0.0001)
        } else {
            XCTFail("Chunk1 should be present in fetched thread1 chunks")
        }
        
        // Fetch all for threadId2
        let thread2Chunks = try sqliteService.getAllChunksByThreadId(threadId2)
        XCTAssertEqual(thread2Chunks.count, 1, "Should fetch exactly 1 chunk for threadId2")
        XCTAssertEqual(thread2Chunks[0].id, chunk3.id)
        XCTAssertEqual(thread2Chunks[0].content, chunk3.content)
        XCTAssertEqual(thread2Chunks[0].threadId, chunk3.threadId)
    }
    
    func testSingleItemCRUD() async throws {
        let itemId = UUID().uuidString
        let threadId = "thread-123"
        let now = Date()
        let item = Item(
            id: itemId,
            type: .email,
            title: "Hello World",
            content: "This is the content",
            embeddableText: "This is the content",
            snippet: "This is…",
            date: now,
            threadId: threadId,
            metadata: [
                "sender": "alice@example.com",
                "labels": ["inbox", "follow_up"]
            ]
        )
        
        let returnedId = try sqliteService.insertItem(item)
        XCTAssertEqual(returnedId, itemId, "insertItem should return the same id")
        
        let fetched = try sqliteService.findItem(id: itemId)
        XCTAssertNotNil(fetched, "findItem should return the inserted item")
        XCTAssertEqual(fetched?.id, item.id)
        XCTAssertEqual(fetched?.type, item.type)
        XCTAssertEqual(fetched?.title, item.title)
        XCTAssertEqual(fetched?.content, item.content)
        XCTAssertEqual(fetched?.snippet, item.snippet)
        XCTAssertEqual(fetched?.threadId, item.threadId)
        
        let delta = abs(fetched!.date.timeIntervalSince(now))
        XCTAssertLessThan(delta, 1.0, "fetched date should be close to inserted date")
        
        let fetchedMeta = fetched!.metadata
        XCTAssertEqual(fetchedMeta["sender"] as? String, "alice@example.com")
        let labels = fetchedMeta["labels"] as? [String]
        XCTAssertEqual(labels, ["inbox", "follow_up"])
    }
    
    func testBatchItemCRUD() async throws {
        let threadA = "thread-A"
        let threadB = "thread-B"
        let now = Date()
        
        let items = [
            Item(
                id: "item-1",
                type: .message,
                title: "Msg 1",
                content: "First message",
                embeddableText: "First message",
                snippet: "First…",
                date: now,
                threadId: threadA
            ),
            Item(
                id: "item-2",
                type: .message,
                title: "Msg 2",
                content: "Second message",
                embeddableText: "Second message",
                snippet: "Second…",
                date: now.addingTimeInterval(60),
                threadId: threadA
            ),
            Item(
                id: "item-3",
                type: .message,
                title: "Msg 3",
                content: "Third message",
                embeddableText: "Third message",
                snippet: "Third…",
                date: now.addingTimeInterval(120),
                threadId: threadB
            ),
        ]
        
        let returnedIds = try sqliteService.insertItems(items)
        XCTAssertEqual(Set(returnedIds), Set(items.map { $0.id }), "insertItems should return all inserted IDs")
        
        let fetchedAll = try sqliteService.findItems(ids: returnedIds)
        XCTAssertEqual(fetchedAll.count, 3, "findItems should return all three items")
        
        let fetchedA = fetchedAll.filter { $0.threadId == threadA }
        XCTAssertEqual(fetchedA.count, 2, "should have two items in thread A")
        let idsA = fetchedA.map { $0.id }
        XCTAssertTrue(idsA.contains("item-1") && idsA.contains("item-2"))
        
        let fetchedB = fetchedAll.filter { $0.threadId == threadB }
        XCTAssertEqual(fetchedB.count, 1, "should have one item in thread B")
        XCTAssertEqual(fetchedB.first?.id, "item-3")
    }
    
    func testSearchIntegration() async throws {
        // 1) Build two email chains: AI conference vs. Baking
        let now = Date()
        
        // ——— AI chain ———
        let aiThreadId = UUID().uuidString
        let aiEmail = Email(
            id: UUID().uuidString,
            originalId: "orig-ai-1",
            threadId: aiThreadId,
            subject: "AI Conference Next Week",
            sender: "alice@example.com",
            recipient: "bob@example.com",
            date: now,
            content: "Hey Bob, are you planning to attend the AI conference in San Francisco next week? They say OpenAI will unveil new models.",
            labels: ["INBOX"],
            snippet: "Hey Bob, are you planning to attend the AI conference…",
            timestamp: Int64(now.timeIntervalSince1970)
        )
        let _ = try sqliteService.insertEmail(aiEmail)
        
        let aiItem = Item(
            id: UUID().uuidString,
            type: .email,
            title: aiEmail.subject,
            content: aiEmail.content,
            embeddableText: aiEmail.content,
            snippet: aiEmail.snippet,
            date: aiEmail.date,
            threadId: aiEmail.threadId,
            metadata: ["sender": aiEmail.sender, "labels": aiEmail.labels]
        )
        let _ = try sqliteService.insertItem(aiItem)
        
        let aiThread = try Thread(from: [aiItem])
        let _ = try sqliteService.insertThread(aiThread)
        
        // embed & index one chunk for the AI thread
        let aiEmbedding = try await embeddingService.embed(text: aiEmail.content)
        let aiChunk = ThreadChunk(
            threadId: aiThread.id,
            parentIds: aiThread.itemIds,
            type: .email,
            content: aiThread.content,
            embedding: aiEmbedding,
            chunkIndex: 0,
            startPosition: 0,
            endPosition: aiThread.content.count
        )
        let _ = try sqliteService.insertThreadChunk(aiChunk)
        
        
        // ——— Baking chain ———
        let bakeThreadId = UUID().uuidString
        let bakeEmail = Email(
            id: UUID().uuidString,
            originalId: "orig-bake-1",
            threadId: bakeThreadId,
            subject: "Weekend Baking Plans",
            sender: "carol@example.com",
            recipient: "dave@example.com",
            date: now,
            content: "Hi Dave, I tried a new sourdough bread recipe this weekend. Want to swap recipes for cakes next time?",
            labels: ["INBOX"],
            snippet: "Hi Dave, I tried a new sourdough bread recipe…",
            timestamp: Int64(now.timeIntervalSince1970)
        )
        let _ = try sqliteService.insertEmail(bakeEmail)
        
        let bakeItem = Item(
            id: UUID().uuidString,
            type: .email,
            title: bakeEmail.subject,
            content: bakeEmail.content,
            embeddableText: bakeEmail.content,
            snippet: bakeEmail.snippet,
            date: bakeEmail.date,
            threadId: bakeEmail.threadId,
            metadata: ["sender": bakeEmail.sender, "labels": bakeEmail.labels]
        )
        let _ = try sqliteService.insertItem(bakeItem)
        
        let bakeThread = try Thread(from: [bakeItem])
        let _ = try sqliteService.insertThread(bakeThread)
        
        // embed & index one chunk for the Baking thread
        let bakeEmbedding = try await embeddingService.embed(text: bakeEmail.content)
        let bakeChunk = ThreadChunk(
            threadId: bakeThread.id,
            parentIds: bakeThread.itemIds,
            type: .email,
            content: bakeThread.content,
            embedding: bakeEmbedding,
            chunkIndex: 0,
            startPosition: 0,
            endPosition: bakeThread.content.count
        )
        let _ = try sqliteService.insertThreadChunk(bakeChunk)
        
        
        // 2) Search for "AI conference" — AI thread should rank #1
        let aiQueryEmbedding = try await embeddingService.embed(text: "AI conference models San Francisco")
        let aiResults = try sqliteService.searchThreadChunks(queryEmbedding: aiQueryEmbedding)
        
        XCTAssertFalse(aiResults.isEmpty, "Search must return at least one result")
        XCTAssertEqual(
            aiResults.first?.thread.id,
            aiThread.id,
            "AI-related query should bring back the AI conference thread first"
        )
        
        // 3) Search for "baking recipes" — Baking thread should rank #1
        let bakeQueryEmbedding = try await embeddingService.embed(text: "baking recipes cakes bread")
        let bakeResults = try sqliteService.searchThreadChunks(queryEmbedding: bakeQueryEmbedding)
        
        XCTAssertFalse(bakeResults.isEmpty, "Search must return at least one result")
        XCTAssertEqual(
            bakeResults.first?.thread.id,
            bakeThread.id,
            "Baking-related query should bring back the baking thread first"
        )
    }

}
