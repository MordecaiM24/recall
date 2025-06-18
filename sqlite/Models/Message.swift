//
//  Message.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import Foundation

struct Message: Identifiable, Hashable {
    let id: String
    let originalId: Int32
    let text: String
    let date: Date
    let timestamp: Int64
    let isFromMe: Bool
    let isSent: Bool
    let service: String
    let contact: String?
    let chatName: String
    let chatId: String
    let createdAt: Date
    
    init(id: String, originalId: Int32, text: String, date: Date, timestamp: Int64,
         isFromMe: Bool, isSent: Bool, service: String, contact: String? = nil,
         chatName: String, chatId: String, createdAt: Date = Date()) {
        self.id = id
        self.originalId = originalId
        self.text = text
        self.date = date
        self.timestamp = timestamp
        self.isFromMe = isFromMe
        self.isSent = isSent
        self.service = service
        self.contact = contact
        self.chatName = chatName
        self.chatId = chatId
        self.createdAt = createdAt
    }
}

extension Message {
    /// text to embed
    var embeddableText: String {
        return text
    }
    
    var preview: String {
        let maxLength = 100
        if text.count <= maxLength {
            return text
        }
        return String(text.prefix(maxLength)) + "..."
    }
    
    var displayName: String {
        if !chatName.isEmpty {
            return chatName
        }
        return contact ?? chatId
    }
    
    var serviceIcon: String {
        switch service.lowercased() {
        case "imessage": return "💬"
        case "sms": return "💬"
        default: return "📱"
        }
    }
}

