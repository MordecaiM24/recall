//
//  contentServiceTests.swift
//  sqliteTests
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import XCTest
@testable import sqlite

class ContentServiceTests: XCTestCase {
    
    var contentService: ContentService!
    var testDBPath: String!
    
    // test constants
    let defaultDBPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] + "/data.db"
    let databaseVersionKey = "database_schema_version"
    let schemaVersion = 2
    
    override func setUp() async throws {
        try await super.setUp()
        
        // create unique test db path for each test
        testDBPath = NSTemporaryDirectory() + "content_test_\(UUID().uuidString).db"
        
        // clean up any existing test db
        try? FileManager.default.removeItem(atPath: testDBPath)
        
        do {
            // create content service with custom db path
            let embeddingService = try EmbeddingService()
            let sqliteService = try SQLiteService(path: testDBPath, embeddingDimensions: embeddingService.embeddingDimensions)
            try sqliteService.setupDatabase()
            
            // manually create content service with our test services
            contentService = try await ContentService(sqliteService: sqliteService, embeddingService: embeddingService)
        } catch {
            XCTFail("failed to setup content service: \(error)")
        }
    }
    
    override func tearDown() async throws {
        contentService = nil
        if let testDBPath = testDBPath {
            try? FileManager.default.removeItem(atPath: testDBPath)
        }
        try await super.tearDown()
    }
    
    // MARK: - Document Operations Tests
    
    func testAddDocument() async throws {
        let title = "test document"
        let content = "this is test content for the document"
        
        let documentId = try await contentService.addDocument(title: title, content: content)
        
        XCTAssertFalse(documentId.isEmpty, "document id should not be empty")
        print("✓ added document with id: \(documentId)")
        
        // verify document was actually stored
        let documents = try await contentService.getAllDocuments()
        XCTAssertGreaterThan(documents.count, 0, "should have at least one document")
        
        let addedDoc = documents.first { $0.id == documentId }
        XCTAssertNotNil(addedDoc, "should find the added document")
        XCTAssertEqual(addedDoc?.title, title)
        XCTAssertEqual(addedDoc?.content, content)
        
        print("✓ document was stored and retrieved correctly")
    }
    
    func testGetAllDocuments() async throws {
        // add a few documents
        _ = try await contentService.addDocument(title: "doc 1", content: "content 1")
        _ = try await contentService.addDocument(title: "doc 2", content: "content 2")
        _ = try await contentService.addDocument(title: "doc 3", content: "content 3")
        
        let documents = try await contentService.getAllDocuments()
        XCTAssertEqual(documents.count, 3, "should have 3 documents")
        
        let titles = documents.map { $0.title }.sorted()
        XCTAssertEqual(titles, ["doc 1", "doc 2", "doc 3"])
        
        print("✓ retrieved all documents correctly")
    }
    
    // MARK: - Message Operations Tests
    
    func testAddMessage() async throws {
        let message = Message(
            id: UUID().uuidString,
            originalId: 123,
            text: "test message content",
            date: Date(),
            timestamp: 123456789,
            isFromMe: true,
            isSent: true,
            service: "iMessage",
            contact: "alice",
            chatName: "alice",
            chatId: "+1234567890"
        )
        
        let messageId = try await contentService.addMessage(message)
        
        XCTAssertFalse(messageId.isEmpty, "message id should not be empty")
        print("✓ added message with id: \(messageId)")
        
        // verify message was stored
        let retrievedMessage = try await contentService.getMessage(id: messageId)
        XCTAssertNotNil(retrievedMessage, "should retrieve the stored message")
        XCTAssertEqual(retrievedMessage?.text, "test message content")
        XCTAssertEqual(retrievedMessage?.contact, "alice")
        
        print("✓ message was stored and retrieved correctly")
    }
    
    // MARK: - Email Operations Tests
    
    func testAddEmail() async throws {
        let email = Email(
            id: UUID().uuidString,
            originalId: "email-123",
            threadId: "thread-123",
            subject: "test email subject",
            sender: "sender@example.com",
            recipient: "recipient@example.com",
            date: Date(),
            content: "this is the email content body",
            labels: ["INBOX"],
            snippet: "email snippet",
            timestamp: 123456789
        )
        
        let emailId = try await contentService.addEmail(email)
        
        XCTAssertFalse(emailId.isEmpty, "email id should not be empty")
        print("✓ added email with id: \(emailId)")
        
        // verify email was stored
        let retrievedEmail = try await contentService.getEmail(id: emailId)
        XCTAssertNotNil(retrievedEmail, "should retrieve the stored email")
        XCTAssertEqual(retrievedEmail?.subject, "test email subject")
        XCTAssertEqual(retrievedEmail?.sender, "sender@example.com")
        
        print("✓ email was stored and retrieved correctly")
    }
    
    // MARK: - Note Operations Tests
    
    func testAddNote() async throws {
        let note = Note(
            id: UUID().uuidString,
            originalId: 456,
            title: "test note",
            snippet: "note snippet",
            content: "this is the note content",
            folder: "Notes",
            modified: Date(),
            modificationTimestamp: 123456789
        )
        
        let noteId = try await contentService.addNote(note)
        
        XCTAssertFalse(noteId.isEmpty, "note id should not be empty")
        print("✓ added note with id: \(noteId)")
        
        // verify note was stored
        let retrievedNote = try await contentService.getNote(id: noteId)
        XCTAssertNotNil(retrievedNote, "should retrieve the stored note")
        XCTAssertEqual(retrievedNote?.title, "test note")
        XCTAssertEqual(retrievedNote?.content, "this is the note content")
        
        print("✓ note was stored and retrieved correctly")
    }
    
    // MARK: - Unified Search Tests
    
    func testUnifiedSearch() async throws {
        // add content across different types with similar themes
        _ = try await contentService.addDocument(
            title: "ai research paper",
            content: "artificial intelligence and machine learning algorithms"
        )
        
        let message = Message(
            id: UUID().uuidString, originalId: 1, text: "let's discuss machine learning today",
            date: Date(), timestamp: 123456789, isFromMe: true, isSent: true,
            service: "iMessage", contact: "alice", chatName: "alice", chatId: "+1234567890"
        )
        _ = try await contentService.addMessage(message)
        
        let email = Email(
            id: UUID().uuidString, originalId: "email1", threadId: "thread1",
            subject: "machine learning conference", sender: "conf@ai.org", recipient: "you@example.com",
            date: Date(), content: "join us for the ai conference", labels: ["INBOX"],
            snippet: "ai conference", timestamp: 123456789
        )
        _ = try await contentService.addEmail(email)
        
        // search for ai-related content
        let results = await contentService.search(query: "artificial intelligence machine learning")
        
        XCTAssertGreaterThan(results.count, 0, "should find ai-related content")
        print("✓ unified search found \(results.count) results")
        
        // verify we get different content types
        let contentTypes = Set(results.map { $0.type })
        XCTAssertGreaterThan(contentTypes.count, 1, "should find multiple content types")
        print("✓ found content types: \(contentTypes.map { $0.displayName })")
        
        // verify similarity scores
        for result in results {
            XCTAssertGreaterThan(result.similarity, 0, "similarity should be positive")
            XCTAssertLessThanOrEqual(result.similarity, 1.0, "similarity should be <= 1.0")
            print("  - \(result.type.displayName): \(result.similarityPercentage)")
        }
    }
    
    func testSearchByContentType() async throws {
        // add different types of content
        _ = try await contentService.addDocument(title: "document about cats", content: "cats are awesome pets")
        
        let message = Message(
            id: UUID().uuidString, originalId: 1, text: "my cat is so cute",
            date: Date(), timestamp: 123456789, isFromMe: true, isSent: true,
            service: "iMessage", contact: "friend", chatName: "friend", chatId: "+1234567890"
        )
        _ = try await contentService.addMessage(message)
        
        let email = Email(
            id: UUID().uuidString, originalId: "email1", threadId: "thread1",
            subject: "cooking recipes", sender: "chef@food.com", recipient: "you@example.com",
            date: Date(), content: "here are some pasta recipes", labels: ["INBOX"],
            snippet: "pasta recipes", timestamp: 123456789
        )
        _ = try await contentService.addEmail(email)
        
        // search only documents
        let documentResults = await contentService.searchDocuments(query: "cats")
        XCTAssertTrue(documentResults.allSatisfy { $0.type == .document }, "should only return documents")
        XCTAssertGreaterThan(documentResults.count, 0, "should find cat-related documents")
        
        // search only messages
        let messageResults = await contentService.searchMessages(query: "cats")
        XCTAssertTrue(messageResults.allSatisfy { $0.type == .message }, "should only return messages")
        XCTAssertGreaterThan(messageResults.count, 0, "should find cat-related messages")
        
        // search only emails
        let emailResults = await contentService.searchEmails(query: "recipes")
        XCTAssertTrue(emailResults.allSatisfy { $0.type == .email }, "should only return emails")
        XCTAssertGreaterThan(emailResults.count, 0, "should find recipe-related emails")
        
        print("✓ content type-specific search works")
    }
    
    func testEmptySearch() async throws {
        // add some content first to make sure empty search isn't just bc no data
        _ = try await contentService.addDocument(title: "test doc", content: "some content")
        
        let results = await contentService.search(query: "")
        XCTAssertEqual(results.count, 0, "empty query should return no results")
        
        let results2 = await contentService.search(query: "   ")
        XCTAssertEqual(results2.count, 0, "whitespace-only query should return no results")
        
        print("✓ empty search handling works")
    }
    
    // MARK: - Batch Operations Tests
    
    func testBatchAddMessages() async throws {
        let messages = [
            Message(
                id: UUID().uuidString, originalId: 1, text: "first message",
                date: Date(), timestamp: 123456789, isFromMe: true, isSent: true,
                service: "iMessage", contact: "alice", chatName: "alice", chatId: "+1111111111"
            ),
            Message(
                id: UUID().uuidString, originalId: 2, text: "second message",
                date: Date(), timestamp: 123456790, isFromMe: false, isSent: true,
                service: "iMessage", contact: "bob", chatName: "bob", chatId: "+2222222222"
            ),
            Message(
                id: UUID().uuidString, originalId: 3, text: "third message",
                date: Date(), timestamp: 123456791, isFromMe: true, isSent: true,
                service: "SMS", contact: "charlie", chatName: "charlie", chatId: "+3333333333"
            )
        ]
        
        let messageIds = try await contentService.addMessages(messages)
        
        XCTAssertEqual(messageIds.count, 3, "should return 3 message ids")
        print("✓ batch added \(messageIds.count) messages")
        
        // verify messages can be searched
        let results = await contentService.searchMessages(query: "message")
        XCTAssertGreaterThanOrEqual(results.count, 3, "should find all added messages")
        
        print("✓ batch message operations work")
    }
    
    func testBatchAddEmails() async throws {
        let emails = [
            Email(
                id: UUID().uuidString, originalId: "email1", threadId: "thread1",
                subject: "first email", sender: "sender1@example.com", recipient: "you@example.com",
                date: Date(), content: "content of first email", labels: ["INBOX"],
                snippet: "first email", timestamp: 123456789
            ),
            Email(
                id: UUID().uuidString, originalId: "email2", threadId: "thread2",
                subject: "second email", sender: "sender2@example.com", recipient: "you@example.com",
                date: Date(), content: "content of second email", labels: ["SENT"],
                snippet: "second email", timestamp: 123456790
            )
        ]
        
        let emailIds = try await contentService.addEmails(emails)
        
        XCTAssertEqual(emailIds.count, 2, "should return 2 email ids")
        print("✓ batch added \(emailIds.count) emails")
        
        // verify emails can be searched
        let results = await contentService.searchEmails(query: "email")
        XCTAssertGreaterThanOrEqual(results.count, 2, "should find all added emails")
        
        print("✓ batch email operations work")
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorHandling() async throws {
        // test retrieving non-existent content
        let nonExistentMessage = try await contentService.getMessage(id: "non-existent-uuid")
        XCTAssertNil(nonExistentMessage, "should return nil for non-existent message")
        
        let nonExistentEmail = try await contentService.getEmail(id: "non-existent-uuid")
        XCTAssertNil(nonExistentEmail, "should return nil for non-existent email")
        
        let nonExistentNote = try await contentService.getNote(id: "non-existent-uuid")
        XCTAssertNil(nonExistentNote, "should return nil for non-existent note")
        
        print("✓ error handling for missing content works")
    }
    
    // MARK: - Performance Tests
    
    func testSearchPerformance() async throws {
        // add a bunch of content for performance testing
        for i in 1...20 {
            _ = try await contentService.addDocument(
                title: "performance test document \(i)",
                content: "this is document \(i) with test content for performance evaluation"
            )
            
            let message = Message(
                id: UUID().uuidString, originalId: Int32(i), text: "performance test message \(i)",
                date: Date(), timestamp: Int64(123456789 + i), isFromMe: i % 2 == 0, isSent: true,
                service: "iMessage", contact: "contact\(i)", chatName: "chat\(i)", chatId: "+\(i)234567890"
            )
            _ = try await contentService.addMessage(message)
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let results = await contentService.search(query: "performance test")
        let searchTime = CFAbsoluteTimeGetCurrent() - startTime
        
        XCTAssertGreaterThan(results.count, 0, "should find performance test content")
        print("✓ searched \(results.count) results in \(String(format: "%.3f", searchTime))s")
        
        // search should be reasonably fast even with multiple content types
        XCTAssertLessThan(searchTime, 2.0, "search should complete within 2 seconds")
    }
    
    func testRelevanceRanking() async throws {
        // add content with varying relevance to test query
        _ = try await contentService.addDocument(
            title: "machine learning guide",
            content: "comprehensive guide to machine learning and artificial intelligence algorithms"
        )
        
        _ = try await contentService.addDocument(
            title: "cooking recipes",
            content: "delicious pasta and pizza recipes for dinner parties"
        )
        
        let message = Message(
            id: UUID().uuidString, originalId: 1, text: "studying machine learning today",
            date: Date(), timestamp: 123456789, isFromMe: true, isSent: true,
            service: "iMessage", contact: "friend", chatName: "study buddy", chatId: "+1234567890"
        )
        _ = try await contentService.addMessage(message)
        
        // search for machine learning content
        let results = await contentService.search(query: "machine learning artificial intelligence")
        
        XCTAssertGreaterThan(results.count, 0, "should find relevant content")
        
        // verify relevance differences exist (allow for very similar scores)
        if results.count >= 2 {
            let sortedBySimilarity = results.sorted { $0.similarity > $1.similarity }
            let topResult = sortedBySimilarity[0]
            let bottomResult = sortedBySimilarity.last!
            
            // use a meaningful difference threshold instead of strict greater than
            let similarityDifference = topResult.similarity - bottomResult.similarity
            XCTAssertGreaterThan(similarityDifference, 0.001,
                               "most and least relevant content should have meaningful similarity difference")
            
            print("✓ relevance ranking works:")
            for (index, result) in sortedBySimilarity.prefix(3).enumerated() {
                print("  \(index + 1). \(result.type.displayName): \(result.similarityPercentage)")
            }
        }
    }
    
    // MARK: - Integration Tests
    
    func testCrossContentTypeSearch() async throws {
        // add content about the same topic across different types
        let topic = "artificial intelligence research"
        
        _ = try await contentService.addDocument(
            title: "AI Research Paper",
            content: "latest developments in artificial intelligence research and neural networks"
        )
        
        let message = Message(
            id: UUID().uuidString, originalId: 1, text: "excited about the new AI research breakthrough!",
            date: Date(), timestamp: 123456789, isFromMe: true, isSent: true,
            service: "iMessage", contact: "researcher", chatName: "lab group", chatId: "+1234567890"
        )
        _ = try await contentService.addMessage(message)
        
        let email = Email(
            id: UUID().uuidString, originalId: "email1", threadId: "thread1",
            subject: "AI Research Conference", sender: "conference@ai.org", recipient: "you@example.com",
            date: Date(), content: "invitation to present your artificial intelligence research",
            labels: ["INBOX"], snippet: "research conference", timestamp: 123456789
        )
        _ = try await contentService.addEmail(email)
        
        let note = Note(
            id: UUID().uuidString, originalId: 1, title: "AI Research Notes",
            content: "key insights from artificial intelligence research papers",
            folder: "Research", modified: Date(), modificationTimestamp: 123456789
        )
        _ = try await contentService.addNote(note)
        
        // search across all content types
        let results = await contentService.search(query: topic)
        
        XCTAssertGreaterThanOrEqual(results.count, 4, "should find content from all types")
        
        let foundTypes = Set(results.map { $0.type })
        XCTAssertEqual(foundTypes.count, 4, "should find all 4 content types")
        XCTAssertTrue(foundTypes.contains(.document))
        XCTAssertTrue(foundTypes.contains(.message))
        XCTAssertTrue(foundTypes.contains(.email))
        XCTAssertTrue(foundTypes.contains(.note))
        
        print("✓ cross-content-type search found content from all types:")
        for type in ContentType.allCases {
            let count = results.filter { $0.type == type }.count
            print("  - \(type.displayName): \(count) results")
        }
    }
    
    @MainActor
    func testLoadingStates() async throws {
        // test that loading states are properly managed
        XCTAssertFalse(contentService.isLoading, "should not be loading initially")
        
        // start a long operation (batch add)
        let messages = (1...5).map { i in
            Message(
                id: UUID().uuidString, originalId: Int32(i), text: "loading test message \(i)",
                date: Date(), timestamp: Int64(123456789 + i), isFromMe: true, isSent: true,
                service: "iMessage", contact: "test", chatName: "test", chatId: "+1234567890"
            )
        }
        
        let addTask = Task {
            return try await contentService.addMessages(messages)
        }
        
        // loading should eventually complete
        let _ = try await addTask.value
        XCTAssertFalse(contentService.isLoading, "should not be loading after completion")
        
        print("✓ loading states managed correctly")
    }
    
    @MainActor
    func testErrorClearance() async {
        // initially no error
        XCTAssertNil(contentService.error, "should have no error initially")
        
        // clear error (should not crash even if no error exists)
        contentService.clearError()
        XCTAssertNil(contentService.error, "should still have no error after clearing")
        
        print("✓ error clearance works")
    }
}
