//
//  SearchResult.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 5/27/25.
//

import Foundation

struct SearchResult: Identifiable {
    let threadChunk: ThreadChunk
    let thread: Thread
    let items: [Item]
    let distance: Double
    
    var id: String { threadChunk.id }

    var similarity: Double {
        return max(0, 1.0 / (1.0 + distance))
    }
    
    var similarityPercentage: String {
        return String(format: "%.1f%%", similarity * 100)
    }
}
