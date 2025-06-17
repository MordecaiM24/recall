//
//  SearchResult.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 5/27/25.
//

import Foundation

struct SearchResult: Identifiable {
    let document: Document
    let distance: Double
    
    var id: String { document.id }

    var similarity: Double {
        // inverse relationship between distance and similarity
        return max(0, 1.0 / (1.0 + distance))
    }
    
    /// formatted similarity percentage
    var similarityPercentage: String {
        return String(format: "%.1f%%", similarity * 100)
    }
}
