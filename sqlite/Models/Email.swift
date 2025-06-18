//
//  Email.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import Foundation

struct Email: Identifiable, Hashable {
    let id: String
    let originalId: String
    let threadId: String
    let subject: String
    let sender: String
    let recipient: String
    let date: Date
    let content: String
    let labels: [String]
    let snippet: String
    let timestamp: Int64
    let createdAt: Date
    
    init(id: String, originalId: String, threadId: String, subject: String,
         sender: String, recipient: String, date: Date, content: String,
         labels: [String] = [], snippet: String, timestamp: Int64,
         createdAt: Date = Date()) {
        self.id = id
        self.originalId = originalId
        self.threadId = threadId
        self.subject = subject
        self.sender = sender
        self.recipient = recipient
        self.date = date
        self.content = content
        self.labels = labels
        self.snippet = snippet
        self.timestamp = timestamp
        self.createdAt = createdAt
    }
}

extension Email {
    /// text to embed (subject + content)
    var embeddableText: String {
        return "\(subject)\n\n\(content)"
    }
    
    var preview: String {
        let maxLength = 200
        if content.count <= maxLength {
            return content
        }
        return String(content.prefix(maxLength)) + "..."
    }
    
    var senderName: String {
        // extract name from "Name <email>" format
        if sender.contains("<") {
            let components = sender.components(separatedBy: "<")
            return components.first?.trimmingCharacters(in: .whitespaces) ?? sender
        }
        return sender
    }
    
    var isInbox: Bool {
        return labels.contains("INBOX")
    }
    
    var isPromotional: Bool {
        return labels.contains("CATEGORY_PROMOTIONS")
    }
}
