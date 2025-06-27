//
//  Item.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/24/25.
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


struct Item: Identifiable {
    let id: String
    let type: ContentType
    let title: String
    let content: String
    let embeddableText: String
    let snippet: String
    // this is glue - change this if possible. threadId is going to be reassigned before we insert in the content service
    // but original thread id's based on the imported data type should be separate from the db generated uuid we create.
    // tbh this could also work as an indicator of whether a thread has been fully imported but that's for >v0.5
    var threadId: String
    let date: Date
    

    let metadata: [String: Any]
    
    init(id: String, type: ContentType, title: String, content: String, embeddableText: String,
         snippet: String, date: Date, threadId: String, metadata: [String: Any] = [:]) {
        self.id = id
        self.type = type
        self.title = title
        self.content = content
        self.embeddableText = embeddableText
        self.snippet = snippet
        self.date = date
        self.threadId = threadId
        self.metadata = metadata
    }
}

extension Item {
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
}

extension Item {
    init(from document: Document) {
        self.init(
            id: document.id,
            type: .document,
            title: document.title,
            content: document.content,
            embeddableText: document.content,
            snippet: document.preview,
            date: document.createdAt,
            threadId: document.id
        )
    }
    
    init(from message: Message) {
        self.init(
            id: message.id,
            type: .message,
            title: message.displayName,
            content: message.text,
            embeddableText: message.embeddableText,
            snippet: message.preview,
            date: message.date,
            threadId: message.contact,
            metadata: [
                // this should be it's own field but then i'd have to adjust sqlite and i don't feel like it
                "originalId": message.originalId,
                "isFromMe": message.isFromMe,
                "service": message.service,
                "contact": message.contact,
                "chatId": message.chatId ?? ""
            ]
        )
    }
    
    init(from email: Email) {
        self.init(
            id: email.id,
            type: .email,
            title: email.subject,
            content: email.content,
            embeddableText: email.embeddableText,
            snippet: email.preview,
            date: email.date,
            threadId: email.threadId,
            metadata: [
                "originalId": email.originalId,
                "sender": email.sender,
                "recipient": email.recipient,
                "labels": email.labels
            ]
        )
    }
    
    init(from note: Note) {
        self.init(
            id: note.id,
            type: .note,
            title: note.displayTitle,
            content: note.content,
            embeddableText: note.embeddableText,
            snippet: note.preview,
            date: note.modified,
            threadId: note.id,
            metadata: [
                "originalId": note.originalId,
                "folder": note.folder,
                "created": note.created?.timeIntervalSince1970 ?? 0
            ]
        )
    }
}
