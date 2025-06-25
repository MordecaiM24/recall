//
//  embeddingTests.swift
//  embeddingTests
//
//  Created by Mordecai Mengesteab on 5/25/25.
//

import Testing
@testable import sqlite

import XCTest

class EmbeddingServiceTests: XCTestCase {
    
    var embeddingService: EmbeddingService!
    
    override func setUp() {
        super.setUp()
        embeddingService = try! EmbeddingService()
    }
    
    override func tearDown() {
        embeddingService = nil
        super.tearDown()
    }
    
    // MARK: - Tokenization Tests
    
    func testEmptyStringTokenization() {
        // empty strings shouldn't crash and should produce valid tokens
        let tokenizer = try! BertTokenizer()
        let result = try! tokenizer.encode(text: "", maxLength: 512)
        
        XCTAssertEqual(result.inputIds.count, 512, "Should pad to max length")
        XCTAssertEqual(result.attentionMask.count, 512, "Attention mask should match")
        
        // should have [CLS] and [SEP] tokens at minimum
        XCTAssertGreaterThan(result.attentionMask.prefix(10).reduce(0, +), 0, "Should have some real tokens")
    }
    
    func testUnicodeTokenization() {
        // unicode (non-ascii) should be handled without crashing or corruption
        let unicodeText = "Hello 🌍 café naïve 中文"
        let tokenizer = try! BertTokenizer()
        
        XCTAssertNoThrow(try tokenizer.encode(text: unicodeText, maxLength: 512),
                         "Unicode text should tokenize without crashing")
    }
    
    // MARK: - Embedding Consistency Tests
    
    func testSameTextSameEmbedding() async {
        // identical input should always produce identical output
        let text = "This is a test document"
        
        let embedding1 = try! await embeddingService.embed(text: text)
        let embedding2 = try! await embeddingService.embed(text: text)
        
        XCTAssertEqual(embedding1.count, embedding2.count, "Embeddings should have same length")
        
        // compare each element (floating point comparison with tolerance)
        for i in 0..<embedding1.count {
            XCTAssertEqual(embedding1[i], embedding2[i], accuracy: 0.0001,
                           "Embedding values should be identical at index \(i)")
        }
    }
    
    func testEmptyStringEmbedding() async {
        // empty string should produce valid embedding, not crash or return zeros
        let embedding = try! await embeddingService.embed(text: "")
        
        XCTAssertEqual(embedding.count, 384, "Should produce correct dimension embedding")
        
        // should not be all zeros (model should still output something meaningful)
        let magnitude = embedding.reduce(0) { $0 + $1 * $1 }
        XCTAssertGreaterThan(magnitude, 0.1, "Embedding should not be near-zero vector")
    }
    
    // MARK: - Vector Properties Tests
    
    func testEmbeddingDimensions() async {
        // all embeddings should have exactly 384 dimensions
        let texts = ["short", "medium length text", "This is a much longer piece of text that should still produce the same dimension output"]
        
        for text in texts {
            let embedding = try! await embeddingService.embed(text: text)
            XCTAssertEqual(embedding.count, 384, "Embedding for '\(text)' should be 384 dimensions")
        }
    }
    
    func testNoInvalidValues() async {
        // embeddings should never contain NaN or infinite values
        // common failure: model produces NaN on edge cases, breaks vector math
        let texts = ["", "normal text", "!!!", "123", "🎉🎉🎉"]
        
        for text in texts {
            let embedding = try! await embeddingService.embed(text: text)
            
            for (i, value) in embedding.enumerated() {
                XCTAssertFalse(value.isNaN, "Value at index \(i) is NaN for text '\(text)'")
                XCTAssertFalse(value.isInfinite, "Value at index \(i) is infinite for text '\(text)'")
                XCTAssertTrue(value.isFinite, "Value at index \(i) is not finite for text '\(text)'")
            }
        }
    }
    
    func testReasonableValueRange() async {
        // sanity check that model isn't producing garbage
        // embedding values should be in reasonable range (typically -2 to 2)
        let embedding = try! await embeddingService.embed(text: "normal text")
        
        for (i, value) in embedding.enumerated() {
            XCTAssertGreaterThan(value, -10.0, "Value at index \(i) is unreasonably small: \(value)")
            XCTAssertLessThan(value, 10.0, "Value at index \(i) is unreasonably large: \(value)")
        }
    }
    
    // MARK: - Similarity Logic Tests
    
    func testIdenticalTextHighSimilarity() async {
        // identical text should have very high similarity (cosine distance near 0)
        let text = "This is a test document"
        let embedding1 = try! await embeddingService.embed(text: text)
        let embedding2 = try! await embeddingService.embed(text: text)
        
        let similarity = cosineSimilarity(embedding1, embedding2)
        XCTAssertGreaterThan(similarity, 0.99, "Identical text should have >99% similarity")
    }
    
    func testRelatedTextSimilarity() async {
        // related text should be more similar than unrelated text
        // pretty much the most important possible thing here lol
        let doc1 = "This is a document about dogs and puppies"
        let doc2 = "This document discusses cats and kittens"
        let unrelated = "The stock market closed higher today"
        
        let embed1 = try! await embeddingService.embed(text: doc1)
        let embed2 = try! await embeddingService.embed(text: doc2)
        let embedUnrelated = try! await embeddingService.embed(text: unrelated)
        
        let similarityRelated = cosineSimilarity(embed1, embed2)
        let similarityUnrelated1 = cosineSimilarity(embed1, embedUnrelated)
        let similarityUnrelated2 = cosineSimilarity(embed2, embedUnrelated)
        
        // related animal docs should be more similar to each other than to stock market doc
        XCTAssertGreaterThan(similarityRelated, similarityUnrelated1,
                             "Related docs should be more similar than unrelated")
        XCTAssertGreaterThan(similarityRelated, similarityUnrelated2,
                             "Related docs should be more similar than unrelated")
    }
    
    func testKeywordOverlapSimilarity() async {
        // docs with shared keywords should be more similar than completely different docs
        let doc1 = "machine learning algorithms"
        let doc2 = "artificial intelligence and machine learning"
        let unrelated = "cooking recipes for dinner"
        
        let embed1 = try! await embeddingService.embed(text: doc1)
        let embed2 = try! await embeddingService.embed(text: doc2)
        let embedUnrelated = try! await embeddingService.embed(text: unrelated)
        
        let similaritySharedKeywords = cosineSimilarity(embed1, embed2)
        let similarityUnrelated = cosineSimilarity(embed1, embedUnrelated)
        
        XCTAssertGreaterThan(similaritySharedKeywords, similarityUnrelated,
                             "Docs with shared keywords should be more similar")
    }
    
    // MARK: - Model Robustness Tests
    
    func testConcurrentEmbedding() async {
        // multiple embedding requests shouldn't interfere with each other
        let texts = ["text one", "text two", "text three", "text four"]
        
        await withTaskGroup(of: [Float].self) { group in
            for text in texts {
                group.addTask {
                    return try! await self.embeddingService.embed(text: text)
                }
            }
            
            var results: [[Float]] = []
            for await embedding in group {
                results.append(embedding)
                XCTAssertEqual(embedding.count, 384, "Concurrent embedding should have correct dimensions")
            }
            
            XCTAssertEqual(results.count, texts.count, "Should get embedding for each input")
        }
    }
    
    func testBatchProcessing() async {
        // batch embedding should produce same results as individual embedding
        let texts = ["first text", "second text", "third text"]
        
        // individual embeddings
        var individualEmbeddings: [[Float]] = []
        for text in texts {
            let embedding = try! await embeddingService.embed(text: text)
            individualEmbeddings.append(embedding)
        }
        
        // batch embeddings
        let batchEmbeddings = try! await embeddingService.embed(texts: texts)
        
        XCTAssertEqual(individualEmbeddings.count, batchEmbeddings.count,
                       "Batch should produce same number of embeddings")
        
        for i in 0..<texts.count {
            let individual = individualEmbeddings[i]
            let batch = batchEmbeddings[i]
            
            XCTAssertEqual(individual.count, batch.count,
                           "Individual and batch embeddings should have same dimensions")
            
            // should be identical (within floating point precision)
            for j in 0..<individual.count {
                XCTAssertEqual(individual[j], batch[j], accuracy: 0.0001,
                               "Individual and batch embeddings should be identical for text \(i), element \(j)")
            }
        }
    }
    
    // MARK: - Helper Functions
    
    /// calculate cosine similarity between two embeddings
    /// returns value between -1 and 1, where 1 is identical
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        
        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        
        guard magnitudeA > 0 && magnitudeB > 0 else { return 0 }
        
        return dotProduct / (magnitudeA * magnitudeB)
    }
}
