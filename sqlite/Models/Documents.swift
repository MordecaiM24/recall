//
//  Documents.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 5/27/25.
//

import Foundation

struct Document: Identifiable, Hashable {
    let id: Int32
    let title: String
    let content: String
    let createdAt: Date
    let embedding: [Float]?
    
    init(id: Int32, title: String, content: String, createdAt: Date = Date(), embedding: [Float]? = nil) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.embedding = embedding
    }
}

extension Document {
    /// text to embed (title + content)
    var embeddableText: String {
        return "\(title)\n\n\(content)"
    }
    
    var preview: String {
        let maxLength = 200
        if content.count <= maxLength {
            return content
        }
        return String(content.prefix(maxLength)) + "..."
    }
}
