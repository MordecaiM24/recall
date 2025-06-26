//
//  Thread.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/20/25.
//

import Foundation

enum ThreadError: Error {
    case InvalidId
}


struct Thread: Identifiable, Hashable {
    let id: String
    let type: ContentType
    let itemIds: [String]
    let threadId: String
    let snippet: String
    let content: String
    let created: Date
    
    init(id: String, type: ContentType, itemIds: [String], threadId: String, snippet: String, content: String, created: Date) {
        self.id = id
        self.type = type
        self.itemIds = itemIds
        self.threadId = threadId
        self.snippet = snippet
        self.content = content
        self.created = created
    }
    
    init(from items: [Item]) throws {
        if (!items.allSatisfy { $0.threadId == items[0].threadId })  {
            throw ThreadError.InvalidId
        }
        
        switch items[0].type {
        case .email: snippet = Email(from: items[0])?.subject ?? items[0].snippet
        case .message: snippet = Message(from: items[0])?.contact ?? items[0].snippet
        default: snippet = items[0].snippet
            
        }
        
        self.id = UUID().uuidString
        self.type = items[0].type
        self.itemIds = items.map(\.self.id)
        self.threadId = items[0].threadId
        self.created = items[0].date
        self.content = items.map { $0.content }.joined(separator: "\n\n----\n\n")
    }
}

struct ThreadChunk {
    let id: String
    let threadId: String
    let parentIds: [String]
    let type: ContentType
    let content: String
    let embedding: [Float]
    let chunkIndex: Int
    let startPosition: Int
    let endPosition: Int
    
    init(id: String, threadId: String, parentIds: [String], type: ContentType, content: String, embedding: [Float], chunkIndex: Int, startPosition: Int, endPosition: Int) {
        self.id = id
        self.threadId = threadId
        self.parentIds = parentIds
        self.type = type
        self.content = content
        self.embedding = embedding
        self.chunkIndex = chunkIndex
        self.startPosition = startPosition
        self.endPosition = endPosition
    }
    
    init(threadId: String, parentIds: [String], type: ContentType, content: String, embedding: [Float], chunkIndex: Int, startPosition: Int, endPosition: Int) {
        self.id = UUID().uuidString
        self.threadId = threadId
        self.parentIds = parentIds
        self.type = type
        self.content = content
        self.embedding = embedding
        self.chunkIndex = chunkIndex
        self.startPosition = startPosition
        self.endPosition = endPosition
    }
}

