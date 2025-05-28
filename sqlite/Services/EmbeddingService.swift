//
//  EmbeddingService.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 5/27/25.
//

import Foundation
import CoreML

enum EmbeddingError: Error {
    case modelNotFound
    case modelLoadFailed(Error)
    case predictionFailed(Error)
    case invalidOutput
    case invalidInput
}

final class EmbeddingService {
    private let tokenizer: BasicTokenizer
    
    /// dimensions of the embedding output
    let embeddingDimensions: Int
    
    init() throws {
        self.tokenizer = BasicTokenizer()
        self.embeddingDimensions = 384
    }
    
    /// generate embedding for text
    func embed(text: String) async throws -> [Float] {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let embedding = try await generateEmbedding(for: text)
                    continuation.resume(returning: embedding)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// generate embeddings for multiple texts (batch processing)
    func embed(texts: [String]) async throws -> [[Float]] {
        // for now, just process sequentially
        // you could optimize this with actual batch processing if your model supports it
        var embeddings: [[Float]] = []
        for text in texts {
            let embedding = try await embed(text: text)
            embeddings.append(embedding)
        }
        return embeddings
    }
    
    private func generateEmbedding(for text: String) async throws -> [Float] {
        // literally the worst possible embedding model
        // hardcodes a map from text (chunked to 384 chars) using utf8 values and maps onto vector
        let dim = self.embeddingDimensions
        var vec = [Float](repeating: 0.0, count: dim)
        let tokenizer = BasicTokenizer()
        let tokens = tokenizer.tokenize(text)
        
        for (i, token) in tokens.enumerated() {
            for (j, char) in token.utf8.enumerated() {
                let idx = (i * 13 + j) % dim // fake hash
                vec[idx] += Float(char) / 255.0
            }
        }
        
        return vec
    }
}

// more placeholder - non working tokenizer
struct BasicTokenizer {
    func tokenize(_ text: String) -> [String] {
        return text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }
}
