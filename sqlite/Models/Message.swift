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
    let contact: String
    let chatName: String?
    let chatId: String?
    let contactNumber: String?
    let createdAt: Date
    
    init(id: String, originalId: Int32, text: String, date: Date, timestamp: Int64,
         isFromMe: Bool, isSent: Bool, service: String, contact: String,
         chatName: String?, chatId: String?, contactNumber: String?, createdAt: Date = Date()) {
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
        self.contactNumber = contactNumber
        self.createdAt = createdAt
    }
}

extension Message {
    /// text to embed
    var embeddableText: String {
        return "\(contact): \(text)"
    }
    
    var preview: String {
        let maxLength = 100
        if text.count <= maxLength {
            return text
        }
        return String(text.prefix(maxLength)) + "..."
    }
    
    var displayName: String {
        return contact
    }
    
    var serviceIcon: String {
        switch service.lowercased() {
        case "imessage": return "💬"
        case "sms": return "💬"
        default: return "📱"
        }
    }
}

extension Message {
    init?(from item: Item) {
        guard item.type == .message else { return nil }
        guard let originalId = item.metadata["originalId"] as? Int32,
              let isFromMe = item.metadata["isFromMe"] as? Bool,
              let service = item.metadata["service"] as? String,
              let contact = item.metadata["contact"] as? String else {
            return nil
        }
        
        self.init(
            id: item.id,
            originalId: originalId,
            text: item.content,
            date: item.date,
            timestamp: Int64(item.date.timeIntervalSince1970),
            isFromMe: isFromMe,
            isSent: true,
            service: service,
            contact: contact,
            chatName: nil,
            chatId: item.metadata["chatId"] as? String,
            contactNumber: nil
        )
    }
}
