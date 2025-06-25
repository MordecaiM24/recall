//
//  Note.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import Foundation

struct Note: Identifiable, Hashable {
    let id: String
    let originalId: Int32
    let title: String
    let snippet: String?
    let content: String
    let folder: String
    let created: Date?
    let modified: Date
    let creationTimestamp: Double?
    let modificationTimestamp: Double
    let createdAt: Date
    
    init(id: String, originalId: Int32, title: String, snippet: String? = nil,
         content: String, folder: String, created: Date? = nil, modified: Date,
         creationTimestamp: Double? = nil, modificationTimestamp: Double,
         createdAt: Date = Date()) {
        self.id = id
        self.originalId = originalId
        self.title = title
        self.snippet = snippet
        self.content = content
        self.folder = folder
        self.created = created
        self.modified = modified
        self.creationTimestamp = creationTimestamp
        self.modificationTimestamp = modificationTimestamp
        self.createdAt = createdAt
    }
}

extension Note {
    /// text to embed (title + content)
    var embeddableText: String {
        return "\(title)\n\n\(content)"
    }
    
    var preview: String {
        if let snippet = snippet, !snippet.isEmpty {
            return snippet
        }
        
        let maxLength = 200
        if content.count <= maxLength {
            return content
        }
        return String(content.prefix(maxLength)) + "..."
    }
    
    var displayTitle: String {
        if title.isEmpty {
            return "Untitled Note"
        }
        return title
    }
}
