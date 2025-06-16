import XCTest
@testable import sqlite // replace with actual module name

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
        print("✓ database setup test passed")
    }
    
    // MARK: - Document Tests
    
    func testDocumentCRUD() async throws {
        let title = "test document"
        let content = "this is some test content for vector search"
        
        // generate embedding
        let embedding = try await embeddingService.embed(text: content)
        XCTAssertEqual(embedding.count, 384, "embedding should have 384 dimensions")
        
        // test insert
        let documentId = try sqliteService.insertDocument(title: title, content: content, embedding: embedding)
        XCTAssertGreaterThan(documentId, 0, "document id should be positive")
        print("✓ inserted document with id: \(documentId)")
        
        // test find by id
        let fetchedDoc = try sqliteService.findDocument(id: documentId)
        XCTAssertNotNil(fetchedDoc, "should be able to fetch inserted document")
        XCTAssertEqual(fetchedDoc?.title, title)
        XCTAssertEqual(fetchedDoc?.content, content)
        print("✓ fetched document by id")
        
        // test find all
        let allDocs = try sqliteService.findAllDocuments()
        XCTAssertGreaterThanOrEqual(allDocs.count, 1, "should have at least one document")
        print("✓ found all documents: \(allDocs.count)")
        
        // test vector search
        let queryEmbedding = try await embeddingService.embed(text: "test content")
        let searchResults = try sqliteService.searchDocuments(queryEmbedding: queryEmbedding, limit: 5)
        XCTAssertGreaterThan(searchResults.count, 0, "should find at least one result")
        XCTAssertEqual(searchResults[0].document.id, documentId, "should find our inserted document")
        print("✓ vector search works, distance: \(searchResults[0].distance)")
    }
    
    // MARK: - Message Tests
    
    func testMessageCRUD() async throws {
        let message = MessageData(
            id: nil,
            originalId: 12345,
            text: "hey, how's it going? 🚀",
            date: "2024-07-25 22:58:40",
            timestamp: 743641120083533952,
            isFromMe: true,
            isSent: true,
            service: "iMessage",
            contact: "john doe",
            chatName: "john",
            chatId: "+19194089091"
        )
        
        // test insert
        let messageId = try sqliteService.insertMessage(message)
        XCTAssertGreaterThan(messageId, 0)
        print("✓ inserted message with id: \(messageId)")
        
        // test find by id
        let fetchedMessage = try sqliteService.findMessage(id: messageId)
        XCTAssertNotNil(fetchedMessage)
        XCTAssertEqual(fetchedMessage?.originalId, 12345)
        XCTAssertEqual(fetchedMessage?.text, "hey, how's it going? 🚀")
        XCTAssertEqual(fetchedMessage?.isFromMe, true)
        XCTAssertEqual(fetchedMessage?.service, "iMessage")
        print("✓ fetched message by id")
        
        // test content embedding
        let embedding = try await embeddingService.embed(text: message.text)
        try sqliteService.insertContentEmbedding(type: .message, contentId: messageId, embedding: embedding)
        print("✓ inserted message embedding")
    }
    
    // MARK: - Email Tests
    
    func testEmailCRUD() async throws {
        let email = EmailData(
            id: nil,
            originalId: "1976a9c6992a327f",
            threadId: "1976a9c6992a327f",
            subject: "three tips to get you started",
            sender: "The Browser Company <hello@diabrowser.com>",
            recipient: "<mgmenges@ncsu.edu>",
            date: "Fri, 13 Jun 2025 18:45:23 +0000",
            content: "hi there,\n\ndena from the browser company here...",
            labels: ["CATEGORY_PROMOTIONS", "INBOX"],
            snippet: "your first day with dia",
            readableDate: "2025-06-13T18:45:23+00:00",
            timestamp: 1749840323
        )
        
        // test insert
        let emailId = try sqliteService.insertEmail(email)
        XCTAssertGreaterThan(emailId, 0)
        print("✓ inserted email with id: \(emailId)")
        
        // test find by id
        let fetchedEmail = try sqliteService.findEmail(id: emailId)
        XCTAssertNotNil(fetchedEmail)
        XCTAssertEqual(fetchedEmail?.originalId, "1976a9c6992a327f")
        XCTAssertEqual(fetchedEmail?.subject, "three tips to get you started")
        XCTAssertEqual(fetchedEmail?.labels.count, 2)
        XCTAssertTrue(fetchedEmail?.labels.contains("INBOX") ?? false)
        print("✓ fetched email by id")
        
        // test content embedding
        let embedding = try await embeddingService.embed(text: email.content)
        try sqliteService.insertContentEmbedding(type: .email, contentId: emailId, embedding: embedding)
        print("✓ inserted email embedding")
    }
    
    // MARK: - Note Tests
    
    func testNoteCRUD() async throws {
        let note = NoteData(
            id: nil,
            originalId: 710,
            title: "2100-(350+200+320+540)‎ = 850",
            snippet: "160-(30+24+64)‎ = 54",
            content: "some calculation notes here with more detailed math",
            folder: "Notes",
            created: "2025-06-13 20:15:14",
            modified: "2025-06-13 20:16:14",
            creationTimestamp: 771538514.0,
            modificationTimestamp: 771538574.484919
        )
        
        // test insert
        let noteId = try sqliteService.insertNote(note)
        XCTAssertGreaterThan(noteId, 0)
        print("✓ inserted note with id: \(noteId)")
        
        // test find by id
        let fetchedNote = try sqliteService.findNote(id: noteId)
        XCTAssertNotNil(fetchedNote)
        XCTAssertEqual(fetchedNote?.originalId, 710)
        XCTAssertEqual(fetchedNote?.title, "2100-(350+200+320+540)‎ = 850")
        XCTAssertEqual(fetchedNote?.folder, "Notes")
        XCTAssertNotNil(fetchedNote?.created)
        print("✓ fetched note by id")
        
        // test content embedding
        let embedding = try await embeddingService.embed(text: note.content)
        try sqliteService.insertContentEmbedding(type: .note, contentId: noteId, embedding: embedding)
        print("✓ inserted note embedding")
    }
    
    // MARK: - Unified Search Tests
    
    func testUnifiedSearch() async throws {
        // insert test data across all types
        let docEmbedding = try await embeddingService.embed(text: "artificial intelligence machine learning")
        let docId = try sqliteService.insertDocument(
            title: "ai research paper",
            content: "artificial intelligence machine learning deep neural networks",
            embedding: docEmbedding
        )
        
        let message = MessageData(
            id: nil, originalId: 1, text: "let's discuss ai and machine learning today",
            date: "2024-01-01 12:00:00", timestamp: 123456789, isFromMe: true, isSent: true,
            service: "iMessage", contact: "alice", chatName: "alice", chatId: "+1234567890"
        )
        let msgId = try sqliteService.insertMessage(message)
        let msgEmbedding = try await embeddingService.embed(text: message.text)
        try sqliteService.insertContentEmbedding(type: .message, contentId: msgId, embedding: msgEmbedding)
        
        let email = EmailData(
            id: nil, originalId: "email123", threadId: "thread123",
            subject: "machine learning conference", sender: "conf@ai.org", recipient: "you@email.com",
            date: "2024-01-01", content: "join us for the machine learning conference next week",
            labels: ["INBOX"], snippet: "ml conference", readableDate: "2024-01-01T00:00:00Z", timestamp: 123456789
        )
        let emailId = try sqliteService.insertEmail(email)
        let emailEmbedding = try await embeddingService.embed(text: email.content)
        try sqliteService.insertContentEmbedding(type: .email, contentId: emailId, embedding: emailEmbedding)
        
        // test unified search
        let queryEmbedding = try await embeddingService.embed(text: "machine learning artificial intelligence")
        let results = try sqliteService.searchAllContent(queryEmbedding: queryEmbedding, limit: 10)
        
        XCTAssertGreaterThan(results.count, 0, "should find results")
        print("✓ unified search found \(results.count) results")
        
        // verify we get different content types
        let contentTypes = Set(results.map { $0.type })
        XCTAssertGreaterThan(contentTypes.count, 1, "should find multiple content types")
        print("✓ found content types: \(contentTypes.map { $0.rawValue })")
        
        // test filtering by content type
        let emailOnlyResults = try sqliteService.searchAllContent(
            queryEmbedding: queryEmbedding,
            limit: 10,
            contentTypes: [.email]
        )
        XCTAssertTrue(emailOnlyResults.allSatisfy { $0.type == .email }, "should only return emails")
        print("✓ content type filtering works")
    }
    
    // MARK: - Chunk Tests
    
    func testChunkOperations() async throws {
        // insert a document first
        let content = "this is a long document that we want to chunk into smaller pieces for better search"
        let docEmbedding = try await embeddingService.embed(text: content)
        let docId = try sqliteService.insertDocument(title: "test doc", content: content, embedding: docEmbedding)
        
        // simulate chunking strategy
        let chunks = [
            "this is a long document that we want",
            "document that we want to chunk into",
            "want to chunk into smaller pieces for",
            "into smaller pieces for better search"
        ]
        
        for (index, chunkText) in chunks.enumerated() {
            let chunkEmbedding = try await embeddingService.embed(text: chunkText)
            let chunkId = try sqliteService.insertChunk(
                type: .document,
                contentId: docId,
                chunkIndex: index,
                text: chunkText,
                startOffset: index * 20,
                endOffset: (index + 1) * 20 + 10
            )
            XCTAssertGreaterThan(chunkId, 0)
            print("✓ inserted chunk \(index) with id: \(chunkId)")
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorHandling() {
        // test finding non-existent records (these return nil, don't throw)
        do {
            let nonExistentDoc = try sqliteService.findDocument(id: 99999)
            XCTAssertNil(nonExistentDoc, "should return nil for non-existent document")
            print("✓ properly handles missing document")
        } catch {
            XCTFail("findDocument should not throw for missing records: \(error)")
        }
        
        do {
            let nonExistentMessage = try sqliteService.findMessage(id: 99999)
            XCTAssertNil(nonExistentMessage, "should return nil for non-existent message")
            print("✓ properly handles missing message")
        } catch {
            XCTFail("findMessage should not throw for missing records: \(error)")
        }
        
        // test with potentially problematic data (this might not throw either, but good to verify)
        let invalidMessage = MessageData(
            id: nil, originalId: 1, text: "", date: "invalid-date",
            timestamp: 0, isFromMe: false, isSent: false, service: "",
            contact: nil, chatName: "", chatId: ""
        )
        
        do {
            _ = try sqliteService.insertMessage(invalidMessage)
            print("✓ handled potentially invalid message data")
        } catch {
            print("✓ caught error for invalid message: \(error)")
        }
        
        // test actual error condition - invalid sql should throw
        XCTAssertThrowsError(try sqliteService.execute("INVALID SQL STATEMENT")) { error in
            print("✓ properly throws error for invalid sql: \(error)")
        }
    }
    
    // MARK: - Performance Tests
    
    func testBatchOperations() async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // insert multiple messages
        var messageIds: [Int32] = []
        for i in 1...50 {
            let message = MessageData(
                id: nil, originalId: Int32(i), text: "test message \(i) with some content",
                date: "2024-01-01 12:00:00", timestamp: Int64(123456789 + i), isFromMe: i % 2 == 0,
                isSent: true, service: "iMessage", contact: "contact\(i)", chatName: "chat\(i)",
                chatId: "+123456789\(i)"
            )
            let msgId = try sqliteService.insertMessage(message)
            messageIds.append(msgId)
            
            // insert embedding
            let embedding = try await embeddingService.embed(text: message.text)
            try sqliteService.insertContentEmbedding(type: .message, contentId: msgId, embedding: embedding)
        }
        
        let insertTime = CFAbsoluteTimeGetCurrent() - startTime
        print("✓ inserted 50 messages with embeddings in \(String(format: "%.2f", insertTime))s")
        
        // test bulk search
        let searchStart = CFAbsoluteTimeGetCurrent()
        let queryEmbedding = try await embeddingService.embed(text: "test message content")
        let searchResults = try sqliteService.searchAllContent(queryEmbedding: queryEmbedding, limit: 20)
        let searchTime = CFAbsoluteTimeGetCurrent() - searchStart
        
        XCTAssertGreaterThan(searchResults.count, 0)
        print("✓ searched \(searchResults.count) results in \(String(format: "%.3f", searchTime))s")
    }
    
    // MARK: - Vector Relevance Tests
    
    func testVectorSearchRelevance() async throws {
        // insert two pieces of content with very different semantic meaning
        let relevantContent = "machine learning artificial intelligence neural networks deep learning"
        let irrelevantContent = "cooking recipes pasta sauce ingredients tomatoes garlic onions"
        
        // insert both documents
        let relevantEmbedding = try await embeddingService.embed(text: relevantContent)
        let relevantDocId = try sqliteService.insertDocument(
            title: "AI Research",
            content: relevantContent,
            embedding: relevantEmbedding
        )
        
        let irrelevantEmbedding = try await embeddingService.embed(text: irrelevantContent)
        let irrelevantDocId = try sqliteService.insertDocument(
            title: "Cooking Guide",
            content: irrelevantContent,
            embedding: irrelevantEmbedding
        )
        
        print("✓ inserted relevant doc id: \(relevantDocId), irrelevant doc id: \(irrelevantDocId)")
        
        // search for something clearly related to the first document
        let queryEmbedding = try await embeddingService.embed(text: "artificial intelligence machine learning")
        let searchResults = try sqliteService.searchDocuments(queryEmbedding: queryEmbedding, limit: 10)
        
        XCTAssertGreaterThanOrEqual(searchResults.count, 2, "should find both documents")
        
        // the relevant document should be ranked higher (lower distance)
        let relevantResult = searchResults.first { $0.document.id == relevantDocId }
        let irrelevantResult = searchResults.first { $0.document.id == irrelevantDocId }
        
        XCTAssertNotNil(relevantResult, "should find relevant document")
        XCTAssertNotNil(irrelevantResult, "should find irrelevant document")
        
        XCTAssertLessThan(relevantResult!.distance, irrelevantResult!.distance,
                         "relevant document should have lower distance (higher relevance)")
        
        print("✓ relevance ranking works:")
        print("  - relevant distance: \(String(format: "%.4f", relevantResult!.distance))")
        print("  - irrelevant distance: \(String(format: "%.4f", irrelevantResult!.distance))")
        
        // also test with unified search to make sure cross-content-type ranking works
        let unifiedResults = try sqliteService.searchAllContent(queryEmbedding: queryEmbedding, limit: 10)
        let relevantUnified = unifiedResults.first { $0.id == relevantDocId && $0.type == .document }
        let irrelevantUnified = unifiedResults.first { $0.id == irrelevantDocId && $0.type == .document }
        
        XCTAssertNotNil(relevantUnified, "should find relevant document in unified search")
        XCTAssertNotNil(irrelevantUnified, "should find irrelevant document in unified search")
        XCTAssertLessThan(relevantUnified!.distance, irrelevantUnified!.distance,
                         "relevance ranking should work in unified search too")
        
        print("✓ unified search relevance ranking works")
    }
    
    func testCrossContentTypeRelevance() async throws {
        // insert similar content across different types to test unified ranking
        let aiContent = "machine learning and artificial intelligence research"
        
        // document
        let docEmbedding = try await embeddingService.embed(text: aiContent)
        let docId = try sqliteService.insertDocument(
            title: "AI Research Paper",
            content: aiContent,
            embedding: docEmbedding
        )
        
        // message with similar content
        let message = MessageData(
            id: nil, originalId: 1, text: "hey, let's discuss machine learning and AI research today",
            date: "2024-01-01 12:00:00", timestamp: 123456789, isFromMe: true, isSent: true,
            service: "iMessage", contact: "alice", chatName: "alice", chatId: "+1234567890"
        )
        let msgId = try sqliteService.insertMessage(message)
        let msgEmbedding = try await embeddingService.embed(text: message.text)
        try sqliteService.insertContentEmbedding(type: .message, contentId: msgId, embedding: msgEmbedding)
        
        // email with very different content
        let email = EmailData(
            id: nil, originalId: "email123", threadId: "thread123",
            subject: "dinner party planning", sender: "friend@email.com", recipient: "you@email.com",
            date: "2024-01-01", content: "let's plan the menu for our dinner party next weekend",
            labels: ["INBOX"], snippet: "dinner planning", readableDate: "2024-01-01T00:00:00Z", timestamp: 123456789
        )
        let emailId = try sqliteService.insertEmail(email)
        let emailEmbedding = try await embeddingService.embed(text: email.content)
        try sqliteService.insertContentEmbedding(type: .email, contentId: emailId, embedding: emailEmbedding)
        
        // search for AI-related content
        let queryEmbedding = try await embeddingService.embed(text: "artificial intelligence research")
        let results = try sqliteService.searchAllContent(queryEmbedding: queryEmbedding, limit: 10)
        
        XCTAssertGreaterThanOrEqual(results.count, 3, "should find all three pieces of content")
        
        // find results for each content type
        let docResult = results.first { $0.id == docId && $0.type == .document }
        let msgResult = results.first { $0.id == msgId && $0.type == .message }
        let emailResult = results.first { $0.id == emailId && $0.type == .email }
        
        XCTAssertNotNil(docResult, "should find document")
        XCTAssertNotNil(msgResult, "should find message")
        XCTAssertNotNil(emailResult, "should find email")
        
        // both AI-related content should rank higher than dinner party email
        XCTAssertLessThan(docResult!.distance, emailResult!.distance,
                         "AI document should rank higher than dinner email")
        XCTAssertLessThan(msgResult!.distance, emailResult!.distance,
                         "AI message should rank higher than dinner email")
        
        print("✓ cross-content-type relevance ranking works:")
        print("  - document distance: \(String(format: "%.4f", docResult!.distance))")
        print("  - message distance: \(String(format: "%.4f", msgResult!.distance))")
        print("  - email distance: \(String(format: "%.4f", emailResult!.distance))")
    }
    
    func testDateParsing() async throws {
        // test different date formats
        let message = MessageData(
            id: nil, originalId: 1, text: "test", date: "2024-07-25 22:58:40",
            timestamp: 743641120083533952, isFromMe: true, isSent: true,
            service: "iMessage", contact: nil, chatName: "", chatId: "+1234567890"
        )
        let msgId = try sqliteService.insertMessage(message)
        let embedding = try await embeddingService.embed(text: message.text)
        try sqliteService.insertContentEmbedding(type: .message, contentId: msgId, embedding: embedding)
        
        let email = EmailData(
            id: nil, originalId: "email1", threadId: "thread1", subject: "test",
            sender: "test@example.com", recipient: "you@example.com", date: "test",
            content: "test content", labels: [], snippet: "test",
            readableDate: "2025-06-13T18:45:23+00:00", timestamp: 1749840323
        )
        let emailId = try sqliteService.insertEmail(email)
        let emailEmbedding = try await embeddingService.embed(text: email.content)
        try sqliteService.insertContentEmbedding(type: .email, contentId: emailId, embedding: emailEmbedding)
        
        // test unified search to ensure date parsing doesn't crash
        let queryEmbedding = try await embeddingService.embed(text: "test")
        let results = try sqliteService.searchAllContent(queryEmbedding: queryEmbedding, limit: 5)
        
        XCTAssertGreaterThan(results.count, 0)
        for result in results {
            XCTAssertNotNil(result.date, "date should be parsed successfully")
            print("✓ parsed date for \(result.type.rawValue): \(result.date)")
        }
    }
}
