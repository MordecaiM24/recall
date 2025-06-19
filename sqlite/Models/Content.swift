//
//  Content.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import Foundation

enum ContentType: String, CaseIterable {
    case document = "document"
    case message = "message"
    case email = "email"
    case note = "note"
    
    var displayName: String {
        switch self {
        case .document: return "Document"
        case .message: return "Message"
        case .email: return "Email"
        case .note: return "Note"
        }
    }
    
    var icon: String {
        switch self {
        case .document: return "document"
        case .message: return "message"
        case .email: return "envelope"
        case .note: return "note.text"
        }
    }
    
    var tableName: String {
        switch self {
        case .document: return "Document"
        case .message: return "Message"
        case .email: return "Email"
        case .note: return "Note"
        }
    }
}

/// unified content wrapper for search results
struct UnifiedContent: Identifiable {
    let id: String
    let type: ContentType
    let title: String
    let content: String
    let snippet: String
    let date: Date
    let distance: Double
    let metadata: [String: Any]
    
    init(id: String, type: ContentType, title: String, content: String,
         snippet: String, date: Date, distance: Double, metadata: [String: Any] = [:]) {
        self.id = id
        self.type = type
        self.title = title
        self.content = content
        self.snippet = snippet
        self.date = date
        self.distance = distance
        self.metadata = metadata
    }
}

extension UnifiedContent {
    var similarity: Double {
        return max(0, 1.0 / (1.0 + distance))
    }
    
    var similarityPercentage: String {
        return String(format: "%.1f%%", similarity * 100)
    }
    
    var displayTitle: String {
        if title.isEmpty {
            return "\(type.displayName) • \(formattedDate)"
        }
        return title
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var typeIcon: String {
        return type.icon
    }
}

// MARK: - Convenience Initializers

extension UnifiedContent {
    init(from document: Document, distance: Double) {
        self.init(
            id: document.id,
            type: .document,
            title: document.title,
            content: document.content,
            snippet: document.preview,
            date: document.createdAt,
            distance: distance
        )
    }
    
    init(from message: Message, distance: Double) {
        self.init(
            id: message.id,
            type: .message,
            title: message.displayName,
            content: message.text,
            snippet: message.preview,
            date: message.date,
            distance: distance,
            metadata: [
                "isFromMe": message.isFromMe,
                "service": message.service,
                "contact": message.contact ?? "",
                "chatId": message.chatId
            ]
        )
    }
    
    init(from email: Email, distance: Double) {
        self.init(
            id: email.id,
            type: .email,
            title: email.subject,
            content: email.content,
            snippet: email.preview,
            date: email.date,
            distance: distance,
            metadata: [
                "sender": email.sender,
                "recipient": email.recipient,
                "threadId": email.threadId,
                "labels": email.labels
            ]
        )
    }
    
    init(from note: Note, distance: Double) {
        self.init(
            id: note.id,
            type: .note,
            title: note.displayTitle,
            content: note.content,
            snippet: note.preview,
            date: note.modified,
            distance: distance,
            metadata: [
                "folder": note.folder,
                "created": note.created?.timeIntervalSince1970 ?? 0
            ]
        )
    }
}
