//
//  Conversions.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import Foundation

// MARK: - Data Model Conversions

extension Message {
    /// convert to sqliteservice data model
    var toData: MessageData {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        return MessageData(
            id: id,
            originalId: originalId,
            text: text,
            date: formatter.string(from: date),
            timestamp: timestamp,
            isFromMe: isFromMe,
            isSent: isSent,
            service: service,
            contact: contact,
            chatName: chatName,
            chatId: chatId
        )
    }
    
    /// create from sqliteservice data model
    init(from data: MessageData) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let parsedDate = formatter.date(from: data.date) ?? Date(timeIntervalSince1970: Double(data.timestamp) / 1_000_000_000)
        
        self.init(
            id: data.id ?? UUID().uuidString,
            originalId: data.originalId,
            text: data.text,
            date: parsedDate,
            timestamp: data.timestamp,
            isFromMe: data.isFromMe,
            isSent: data.isSent,
            service: data.service,
            contact: data.contact,
            chatName: data.chatName,
            chatId: data.chatId
        )
    }
}

extension Email {
    /// convert to sqliteservice data model
    var toData: EmailData {
        let formatter = ISO8601DateFormatter()
        let labelsJson = try? JSONSerialization.data(withJSONObject: labels, options: [])
        
        return EmailData(
            id: id,
            originalId: originalId,
            threadId: threadId,
            subject: subject,
            sender: sender,
            recipient: recipient,
            date: formatter.string(from: date),
            content: content,
            labels: labels,
            snippet: snippet,
            readableDate: formatter.string(from: date),
            timestamp: timestamp
        )
    }
    
    /// create from sqliteservice data model
    init(from data: EmailData) {
        let formatter = ISO8601DateFormatter()
        let parsedDate = formatter.date(from: data.readableDate) ?? Date(timeIntervalSince1970: Double(data.timestamp))
        
        self.init(
            id: data.id ?? UUID().uuidString,
            originalId: data.originalId,
            threadId: data.threadId,
            subject: data.subject,
            sender: data.sender,
            recipient: data.recipient,
            date: parsedDate,
            content: data.content,
            labels: data.labels,
            snippet: data.snippet,
            timestamp: data.timestamp
        )
    }
}

extension Note {
    /// convert to sqliteservice data model
    var toData: NoteData {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        return NoteData(
            id: id,
            originalId: originalId,
            title: title,
            snippet: snippet,
            content: content,
            folder: folder,
            created: created.map(formatter.string),
            modified: formatter.string(from: modified),
            creationTimestamp: creationTimestamp,
            modificationTimestamp: modificationTimestamp
        )
    }
    
    /// create from sqliteservice data model
    init(from data: NoteData) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        let createdDate = data.created.flatMap(formatter.date)
        let modifiedDate = formatter.date(from: data.modified) ?? Date(timeIntervalSinceReferenceDate: data.modificationTimestamp)
        
        self.init(
            id: data.id ?? UUID().uuidString,
            originalId: data.originalId,
            title: data.title,
            snippet: data.snippet,
            content: data.content,
            folder: data.folder,
            created: createdDate,
            modified: modifiedDate,
            creationTimestamp: data.creationTimestamp,
            modificationTimestamp: data.modificationTimestamp
        )
    }
}
