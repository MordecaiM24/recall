//
//  Documents.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 5/27/25.
//

import Foundation

struct Document: Identifiable, Hashable {
    let id: String
    let title: String
    let content: String
    let createdAt: Date
    
    init(id: String, title: String, content: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
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
