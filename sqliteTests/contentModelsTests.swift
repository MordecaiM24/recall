//
//  contentModelsTest.swift
//  sqliteTests
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import XCTest
@testable import sqlite

class ContentModelsTests: XCTestCase {
    
    // MARK: - ContentType Tests
    
    func testContentTypeProperties() {
        XCTAssertEqual(ContentType.document.rawValue, "document")
        XCTAssertEqual(ContentType.message.rawValue, "message")
        XCTAssertEqual(ContentType.email.rawValue, "email")
        XCTAssertEqual(ContentType.note.rawValue, "note")
        
        XCTAssertEqual(ContentType.document.displayName, "Document")
        XCTAssertEqual(ContentType.message.displayName, "Message")
        XCTAssertEqual(ContentType.email.displayName, "Email")
        XCTAssertEqual(ContentType.note.displayName, "Note")
        
        XCTAssertEqual(ContentType.document.icon, "📄")
        XCTAssertEqual(ContentType.message.icon, "💬")
        XCTAssertEqual(ContentType.email.icon, "📧")
        XCTAssertEqual(ContentType.note.icon, "📝")
        
        XCTAssertEqual(ContentType.document.tableName, "Document")
        XCTAssertEqual(ContentType.message.tableName, "Message")
        XCTAssertEqual(ContentType.email.tableName, "Email")
        XCTAssertEqual(ContentType.note.tableName, "Note")
        
        print("✓ content type properties work correctly")
    }
    
    // MARK: - Message Tests
    
    func testMessageModel() {
        let message = Message(
            id: "test-uuid",
            originalId: 12345,
            text: "hey there! 👋",
            date: Date(),
            timestamp: 743641120083533952,
            isFromMe: true,
            isSent: true,
            service: "iMessage",
            contact: "john doe",
            chatName: "john",
            chatId: "+19194089091"
        )
        
        XCTAssertEqual(message.id, "test-uuid")
        XCTAssertEqual(message.originalId, 12345)
        XCTAssertEqual(message.text, "hey there! 👋")
        XCTAssertEqual(message.isFromMe, true)
        XCTAssertEqual(message.service, "iMessage")
        XCTAssertEqual(message.contact, "john doe")
        XCTAssertEqual(message.chatName, "john")
        XCTAssertEqual(message.chatId, "+19194089091")
        
        print("✓ message model properties work")
    }
    
    func testMessageExtensions() {
        let message = Message(
            id: "test-uuid",
            originalId: 1,
            text: "this is a very long message that should be truncated when we preview it because it exceeds the max length",
            date: Date(),
            timestamp: 123456789,
            isFromMe: false,
            isSent: true,
            service: "iMessage",
            contact: "alice",
            chatName: "alice chat",
            chatId: "+1234567890"
        )
        
        XCTAssertEqual(message.embeddableText, "this is a very long message that should be truncated when we preview it because it exceeds the max length")
        XCTAssertTrue(message.preview.hasSuffix("..."), "long messages should be truncated with ellipsis")
        XCTAssertEqual(message.displayName, "alice chat")
        XCTAssertEqual(message.serviceIcon, "💬")
        
        // test with empty chat name
        let messageWithoutChatName = Message(
            id: "test-uuid2", originalId: 2, text: "test", date: Date(), timestamp: 123456789,
            isFromMe: true, isSent: true, service: "SMS", contact: "bob", chatName: "", chatId: "+0987654321"
        )
        XCTAssertEqual(messageWithoutChatName.displayName, "bob")
        
        print("✓ message extensions work correctly")
    }
    
    // MARK: - Email Tests
    
    func testEmailModel() {
        let email = Email(
            id: "email-uuid",
            originalId: "1976a9c6992a327f",
            threadId: "thread-123",
            subject: "test email subject",
            sender: "Test Sender <test@example.com>",
            recipient: "you@example.com",
            date: Date(),
            content: "this is the email content body",
            labels: ["INBOX", "CATEGORY_PROMOTIONS"],
            snippet: "email snippet",
            timestamp: 1749840323
        )
        
        XCTAssertEqual(email.id, "email-uuid")
        XCTAssertEqual(email.originalId, "1976a9c6992a327f")
        XCTAssertEqual(email.subject, "test email subject")
        XCTAssertEqual(email.sender, "Test Sender <test@example.com>")
        XCTAssertEqual(email.labels.count, 2)
        XCTAssertTrue(email.labels.contains("INBOX"))
        
        print("✓ email model properties work")
    }
    
    func testEmailExtensions() {
        let email = Email(
            id: "email-uuid",
            originalId: "test-email",
            threadId: "thread-123",
            subject: "important email",
            sender: "John Smith <john@company.com>",
            recipient: "you@example.com",
            date: Date(),
            content: "this is a very long email content that should be truncated with ellipses when displayed as a preview because it exceeds the maximum length limit that we have set for email previews in our application interface",
            labels: ["INBOX", "CATEGORY_PROMOTIONS"],
            snippet: "short snippet",
            timestamp: 1749840323
        )
        
        XCTAssertEqual(email.embeddableText, "important email\n\nthis is a very long email content that should be truncated with ellipses when displayed as a preview because it exceeds the maximum length limit that we have set for email previews in our application interface")
        XCTAssertTrue(email.preview.hasSuffix("..."), "long email content should be truncated")
        XCTAssertEqual(email.senderName, "John Smith")
        XCTAssertTrue(email.isInbox)
        XCTAssertTrue(email.isPromotional)
        
        // test sender without angle brackets
        let simpleEmail = Email(
            id: "simple-email", originalId: "simple", threadId: "thread", subject: "test",
            sender: "simple@example.com", recipient: "you@example.com", date: Date(),
            content: "test", labels: ["SENT"], snippet: "test", timestamp: 123456789
        )
        XCTAssertEqual(simpleEmail.senderName, "simple@example.com")
        XCTAssertFalse(simpleEmail.isInbox)
        XCTAssertFalse(simpleEmail.isPromotional)
        
        print("✓ email extensions work correctly")
    }
    
    // MARK: - Note Tests
    
    func testNoteModel() {
        let note = Note(
            id: "note-uuid",
            originalId: 710,
            title: "calculation note",
            snippet: "some math calculations",
            content: "detailed mathematical content here",
            folder: "Notes",
            created: Date(),
            modified: Date(),
            creationTimestamp: 771538514.0,
            modificationTimestamp: 771538574.484919
        )
        
        XCTAssertEqual(note.id, "note-uuid")
        XCTAssertEqual(note.originalId, 710)
        XCTAssertEqual(note.title, "calculation note")
        XCTAssertEqual(note.snippet, "some math calculations")
        XCTAssertEqual(note.folder, "Notes")
        
        print("✓ note model properties work")
    }
    
    func testNoteExtensions() {
        let note = Note(
            id: "note-uuid",
            originalId: 710,
            title: "my note title",
            snippet: "custom snippet",
            content: "this is the full note content with lots of detail",
            folder: "Personal",
            created: Date(),
            modified: Date(),
            modificationTimestamp: 771538574.484919
        )
        
        XCTAssertEqual(note.embeddableText, "my note title\n\nthis is the full note content with lots of detail")
        XCTAssertEqual(note.preview, "custom snippet")
        XCTAssertEqual(note.displayTitle, "my note title")
        
        // test note without snippet
        let noteWithoutSnippet = Note(
            id: "note-uuid2", originalId: 711, title: "another note", content: "content here",
            folder: "Work", modified: Date(), modificationTimestamp: 123456789
        )
        XCTAssertTrue(noteWithoutSnippet.preview.contains("content here"))
        
        // test note without title
        let noteWithoutTitle = Note(
            id: "note-uuid3", originalId: 712, title: "", content: "untitled content",
            folder: "Notes", modified: Date(), modificationTimestamp: 123456789
        )
        XCTAssertEqual(noteWithoutTitle.displayTitle, "Untitled Note")
        
        print("✓ note extensions work correctly")
    }
    
    // MARK: - UnifiedContent Tests
    
    func testUnifiedContentFromDocument() {
        let document = Document(
            id: "doc-uuid",
            title: "test document",
            content: "document content here",
            createdAt: Date()
        )
        
        let unifiedContent = UnifiedContent(from: document, distance: 0.5)
        
        XCTAssertEqual(unifiedContent.id, "doc-uuid")
        XCTAssertEqual(unifiedContent.type, .document)
        XCTAssertEqual(unifiedContent.title, "test document")
        XCTAssertEqual(unifiedContent.content, "document content here")
        XCTAssertEqual(unifiedContent.distance, 0.5)
        XCTAssertEqual(unifiedContent.typeIcon, "📄")
        
        print("✓ unified content from document works")
    }
    
    func testUnifiedContentFromMessage() {
        let message = Message(
            id: "msg-uuid", originalId: 123, text: "hello world", date: Date(),
            timestamp: 123456789, isFromMe: true, isSent: true, service: "iMessage",
            contact: "alice", chatName: "alice chat", chatId: "+1234567890"
        )
        
        let unifiedContent = UnifiedContent(from: message, distance: 0.3)
        
        XCTAssertEqual(unifiedContent.id, "msg-uuid")
        XCTAssertEqual(unifiedContent.type, .message)
        XCTAssertEqual(unifiedContent.title, "alice chat")
        XCTAssertEqual(unifiedContent.content, "hello world")
        XCTAssertEqual(unifiedContent.distance, 0.3)
        XCTAssertEqual(unifiedContent.typeIcon, "💬")
        
        // verify metadata
        XCTAssertEqual(unifiedContent.metadata["isFromMe"] as? Bool, true)
        XCTAssertEqual(unifiedContent.metadata["service"] as? String, "iMessage")
        
        print("✓ unified content from message works")
    }
    
    func testUnifiedContentSimilarity() {
        let content = UnifiedContent(
            id: "test-id",
            type: .document,
            title: "test",
            content: "content",
            snippet: "snippet",
            date: Date(),
            distance: 1.0
        )
        
        let similarity = content.similarity
        XCTAssertGreaterThan(similarity, 0)
        XCTAssertLessThanOrEqual(similarity, 1.0)
        
        let percentage = content.similarityPercentage
        XCTAssertTrue(percentage.hasSuffix("%"))
        
        print("✓ similarity calculations work: \(percentage)")
    }
    
    // MARK: - Model Conversion Tests
    
    func testMessageDataConversion() {
        let message = Message(
            id: "msg-uuid", originalId: 123, text: "test message", date: Date(),
            timestamp: 123456789, isFromMe: true, isSent: true, service: "iMessage",
            contact: "alice", chatName: "alice", chatId: "+1234567890"
        )
        
        let messageData = message.toData
        XCTAssertEqual(messageData.id, "msg-uuid")
        XCTAssertEqual(messageData.originalId, 123)
        XCTAssertEqual(messageData.text, "test message")
        XCTAssertEqual(messageData.isFromMe, true)
        
        // test round trip conversion
        let convertedBack = Message(from: messageData)
        XCTAssertEqual(convertedBack.id, message.id)
        XCTAssertEqual(convertedBack.originalId, message.originalId)
        XCTAssertEqual(convertedBack.text, message.text)
        XCTAssertEqual(convertedBack.isFromMe, message.isFromMe)
        
        print("✓ message data conversion works")
    }
    
    func testEmailDataConversion() {
        let email = Email(
            id: "email-uuid", originalId: "email123", threadId: "thread123",
            subject: "test subject", sender: "test@example.com", recipient: "you@example.com",
            date: Date(), content: "email content", labels: ["INBOX"], snippet: "snippet",
            timestamp: 123456789
        )
        
        let emailData = email.toData
        XCTAssertEqual(emailData.id, "email-uuid")
        XCTAssertEqual(emailData.originalId, "email123")
        XCTAssertEqual(emailData.subject, "test subject")
        XCTAssertEqual(emailData.labels, ["INBOX"])
        
        // test round trip conversion
        let convertedBack = Email(from: emailData)
        XCTAssertEqual(convertedBack.id, email.id)
        XCTAssertEqual(convertedBack.originalId, email.originalId)
        XCTAssertEqual(convertedBack.subject, email.subject)
        XCTAssertEqual(convertedBack.labels, email.labels)
        
        print("✓ email data conversion works")
    }
    
    func testNoteDataConversion() {
        let note = Note(
            id: "note-uuid", originalId: 710, title: "test note", snippet: "snippet",
            content: "note content", folder: "Notes", created: Date(), modified: Date(),
            modificationTimestamp: 123456789
        )
        
        let noteData = note.toData
        XCTAssertEqual(noteData.id, "note-uuid")
        XCTAssertEqual(noteData.originalId, 710)
        XCTAssertEqual(noteData.title, "test note")
        XCTAssertEqual(noteData.folder, "Notes")
        
        // test round trip conversion
        let convertedBack = Note(from: noteData)
        XCTAssertEqual(convertedBack.id, note.id)
        XCTAssertEqual(convertedBack.originalId, note.originalId)
        XCTAssertEqual(convertedBack.title, note.title)
        XCTAssertEqual(convertedBack.folder, note.folder)
        
        print("✓ note data conversion works")
    }
}
