//
//  EmbeddingService.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 5/27/25.

//  BertTokenizer.swift
//  sqlite
//
//  Adapted from HuggingFace CoreMLBert

import Foundation
import CoreML

// MARK: - Utils Helper
class Utils {
    static func substr(_ str: String, _ range: Range<Int>) -> String? {
        guard range.lowerBound >= 0 && range.upperBound <= str.count else { return nil }
        let start = str.index(str.startIndex, offsetBy: range.lowerBound)
        let end = str.index(str.startIndex, offsetBy: range.upperBound)
        return String(str[start..<end])
    }
}

// MARK: - Tokenization Result
struct TokenizationResult {
    let inputIds: [Int]
    let attentionMask: [Int]
}

// MARK: - BERT Tokenizer
enum TokenizerError: Error {
    case tooLong(String)
    case vocabNotFound
}

class BertTokenizer {
    private let basicTokenizer = BasicTokenizer()
    private let wordpieceTokenizer: WordpieceTokenizer
    private let maxLen = 512
    
    private let vocab: [String: Int]
    private let ids_to_tokens: [Int: String]
    
    init() throws {
        guard let url = Bundle.main.url(forResource: "vocab", withExtension: "txt") else {
            throw TokenizerError.vocabNotFound
        }
        let vocabTxt = try String(contentsOf: url, encoding: .utf8)
        let tokens = vocabTxt.split(separator: "\n").map { String($0) }
        
        var vocab: [String: Int] = [:]
        var ids_to_tokens: [Int: String] = [:]
        for (i, token) in tokens.enumerated() {
            vocab[token] = i
            ids_to_tokens[i] = token
        }
        self.vocab = vocab
        self.ids_to_tokens = ids_to_tokens
        self.wordpieceTokenizer = WordpieceTokenizer(vocab: self.vocab)
    }
    
    func tokenize(text: String) -> [String] {
        var tokens: [String] = []
        for token in basicTokenizer.tokenize(text: text) {
            for subToken in wordpieceTokenizer.tokenize(word: token) {
                tokens.append(subToken)
            }
        }
        return tokens
    }
    
    /// Main entry point for sentence transformer models
    func encode(text: String, maxLength: Int = 512) throws -> TokenizationResult {
        // Tokenize the text
        let tokens = tokenize(text: text)
        
        // Add special tokens: [CLS] + tokens + [SEP]
        let withSpecials = ["[CLS]"] + tokens + ["[SEP]"]
        
        // Truncate non special tokens
        let truncated = Array(withSpecials.prefix(maxLength))
        
        // Convert to IDs
        let tokenIds = truncated.map { vocab[$0] ?? vocab["[UNK]"]! }
        
        
        // Create attention mask (1 for real tokens, 0 for padding)
        let realTokenCount = tokenIds.count
        let attentionMask = Array(repeating: 1, count: realTokenCount) +
                          Array(repeating: 0, count: maxLength - realTokenCount)
        
        // Pad input IDs to maxLength
        let paddedIds = tokenIds + Array(repeating: 0, count: maxLength - realTokenCount)
        
        return TokenizationResult(inputIds: paddedIds, attentionMask: attentionMask)
    }
    
    func tokenToId(token: String) -> Int {
        return vocab[token] ?? vocab["[UNK]"] ?? 0
    }
    
    func unTokenize(tokens: [Int]) -> [String] {
        return tokens.compactMap { ids_to_tokens[$0] }
    }
}

// MARK: - Basic Tokenizer
class BasicTokenizer {
    let neverSplit = [
        "[UNK]", "[SEP]", "[PAD]", "[CLS]", "[MASK]"
    ]
    
    func tokenize(text: String) -> [String] {
        let splitTokens = text.folding(options: .diacriticInsensitive, locale: nil)
            .components(separatedBy: NSCharacterSet.whitespaces)
        let tokens = splitTokens.flatMap({ (token: String) -> [String] in
            if neverSplit.contains(token) {
                return [token]
            }
            var toks: [String] = []
            var currentTok = ""
            for c in token.lowercased() {
                if c.isLetter || c.isNumber || c == "°" {
                    currentTok += String(c)
                } else if currentTok.count > 0 {
                    toks.append(currentTok)
                    toks.append(String(c))
                    currentTok = ""
                } else {
                    toks.append(String(c))
                }
            }
            if currentTok.count > 0 {
                toks.append(currentTok)
            }
            return toks
        })
        return tokens.filter { !$0.isEmpty }
    }
}

// MARK: - Wordpiece Tokenizer
class WordpieceTokenizer {
    private let unkToken = "[UNK]"
    private let maxInputCharsPerWord = 100
    private let vocab: [String: Int]
    
    init(vocab: [String: Int]) {
        self.vocab = vocab
    }
    
    func tokenize(word: String) -> [String] {
        if word.count > maxInputCharsPerWord {
            return [unkToken]
        }
        var outputTokens: [String] = []
        var isBad = false
        var start = 0
        var subTokens: [String] = []
        while start < word.count {
            var end = word.count
            var cur_substr: String? = nil
            while start < end {
                guard var substr = Utils.substr(word, start..<end) else { break }
                if start > 0 {
                    substr = "##\(substr)"
                }
                if vocab[substr] != nil {
                    cur_substr = substr
                    break
                }
                end -= 1
            }
            if cur_substr == nil {
                isBad = true
                break
            }
            subTokens.append(cur_substr!)
            start = end
        }
        if isBad {
            outputTokens.append(unkToken)
        } else {
            outputTokens.append(contentsOf: subTokens)
        }
        return outputTokens
    }
}

// MARK: - Updated EmbeddingService
enum EmbeddingError: Error {
    case modelNotFound
    case modelLoadFailed(Error)
    case predictionFailed(Error)
    case invalidOutput
    case invalidInput
    case tokenizerInitFailed
}

final class EmbeddingService {
    private let tokenizer: BertTokenizer
    private let model: all_MiniLM_L6_v2
    
    /// dimensions of the embedding output
    let embeddingDimensions: Int
    
    init() throws {
        // Initialize tokenizer
        do {
            self.tokenizer = try BertTokenizer()
        } catch {
            throw EmbeddingError.tokenizerInitFailed
        }
        
        // Load CoreML model using auto-generated class
        do {
            self.model = try all_MiniLM_L6_v2(configuration: MLModelConfiguration())
        } catch {
            throw EmbeddingError.modelLoadFailed(error)
        }
        
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
        var embeddings: [[Float]] = []
        for text in texts {
            let embedding = try await embed(text: text)
            embeddings.append(embedding)
        }
        return embeddings
    }
    
    private func generateEmbedding(for text: String) async throws -> [Float] {
        // Tokenize the input text
        let tokenizationResult = try tokenizer.encode(text: text, maxLength: 512)
        
        // Create MLMultiArray for input_ids
        guard let inputIdsArray = try? MLMultiArray(shape: [1, 512], dataType: .float32) else {
            throw EmbeddingError.invalidInput
        }
        
        // Create MLMultiArray for attention_mask
        guard let attentionMaskArray = try? MLMultiArray(shape: [1, 512], dataType: .float32) else {
            throw EmbeddingError.invalidInput
        }
        
        // Fill the arrays
        for i in 0..<512 {
            inputIdsArray[i] = NSNumber(value: Float(tokenizationResult.inputIds[i]))
            attentionMaskArray[i] = NSNumber(value: Float(tokenizationResult.attentionMask[i]))
        }
        
        // Run inference using the auto-generated class
        do {
            let output = try model.prediction(input_ids: inputIdsArray, attention_mask: attentionMaskArray)
            
            // Extract embeddings from the output
            let embeddingsMultiArray = output.embeddings
            
            // Convert MLMultiArray to [Float]
            var embeddings: [Float] = []
            let count = embeddingsMultiArray.count
            for i in 0..<count {
                embeddings.append(embeddingsMultiArray[i].floatValue)
            }
            
            return embeddings
            
        } catch {
            throw EmbeddingError.predictionFailed(error)
        }
    }
}



struct ChunkingConfig {
    let windowSize: Int = 512
    let overlapSize: Int
    
    init(overlapSize: Int = 128) {
        self.overlapSize = overlapSize
    }
}


extension EmbeddingService {
    func createThreadChunks(
        from thread: Thread,
        config: ChunkingConfig = ChunkingConfig()
    ) async throws -> [ThreadChunk] {
        let content = thread.content
        let threadId = thread.threadId
        let parentIds = thread.itemIds
        
        let type = thread.type
        
        let allTokens = tokenizer.tokenize(text: content)
        
        var chunks: [ThreadChunk] = []
        
        guard !allTokens.isEmpty else {
            return chunks
        }
        
        var chunkIndex = 0
        var startTokenIndex = 0
        
        while startTokenIndex < allTokens.count {
            let endTokenIndex = min(startTokenIndex + config.windowSize, allTokens.count)
            
            let chunkTokens = Array(allTokens[startTokenIndex ..< endTokenIndex])
            
            let chunkText = reconstructTextFromTokens(chunkTokens)
            
            let (startPos, endPos) = calculateCharacterPositions(
                content: content,
                tokens: allTokens,
                startTokenIndex: startTokenIndex,
                endTokenIndex: endTokenIndex
            )
            
            let embedding = try await embed(text: chunkText)
            
            let chunk = ThreadChunk(
                threadId: threadId,
                parentIds: parentIds,
                type: type,
                content: chunkText,
                embedding: embedding,
                chunkIndex: chunkIndex,
                startPosition: startPos,
                endPosition: endPos
            )
            
            chunks.append(chunk)
            chunkIndex += 1
            
            let stepSize = config.windowSize - config.overlapSize
            startTokenIndex += stepSize
            
            if endTokenIndex >= allTokens.count {
                break
            }
        }
        
        return chunks
    }
    
    private func reconstructTextFromTokens(_ tokens: [String]) -> String {
        let cleanedTokens = tokens.map { token in
            if token.hasPrefix("##") {
                return String(token.dropFirst(2))
            }
            return token
        }.filter { !["[CLS]", "[SEP]", "[PAD]"].contains($0) }
        
        
        return cleanedTokens.joined(separator: " ")
    }
    
    func calculateCharacterPositions(content: String, tokens: [String], startTokenIndex: Int, endTokenIndex: Int) -> (Int, Int) {
        
        guard !tokens.isEmpty else { return (0,0) }
        
        let startToken = findFirstContentToken(tokens: tokens, fromIndex: startTokenIndex)
        let endToken = findLastContentToken(tokens: tokens, toIndex: endTokenIndex - 1)
        
        let lowercaseContent = content.lowercased()
        
        let startPos: Int
        if let startToken = startToken {
            let cleanToken = cleanTokenForSearch(startToken)
            
            if let range = lowercaseContent.range(of: cleanToken) {
                startPos = lowercaseContent.distance(from: lowercaseContent.startIndex, to: range.lowerBound)
            } else {
                startPos = 0
            }
        } else {
            startPos = 0
        }
        
        let endPos: Int
        if let endToken = endToken {
            let cleanToken = cleanTokenForSearch(endToken)
            // search from start position to avoid matching earlier occurrences
            let searchStart = lowercaseContent.index(lowercaseContent.startIndex, offsetBy: startPos)
            let searchRange = searchStart..<lowercaseContent.endIndex
            
            if let range = lowercaseContent.range(of: cleanToken, options: .backwards, range: searchRange) {
                endPos = lowercaseContent.distance(from: lowercaseContent.startIndex, to: range.upperBound)
            } else {
                endPos = content.count
            }
        } else {
            endPos = content.count
        }
        
        return (startPos, min(endPos, content.count))

    }
    
    private func findFirstContentToken(tokens: [String], fromIndex: Int) -> String? {
        let specialTokens = Set(["[CLS]", "[SEP]", "[PAD]", "[UNK]", "[MASK]"])
        
        for i in fromIndex..<tokens.count {
            let token = tokens[i]
            if !specialTokens.contains(token) && !token.isEmpty {
                return token
            }
        }
        return nil
    }
    
    private func findLastContentToken(tokens: [String], toIndex: Int) -> String? {
        let specialTokens = Set(["[CLS]", "[SEP]", "[PAD]", "[UNK]", "[MASK]"])
        
        for i in stride(from: toIndex, through: 0, by: -1) {
            let token = tokens[i]
            if !specialTokens.contains(token) && !token.isEmpty {
                return token
            }
        }
        return nil
    }
    
    private func cleanTokenForSearch(_ token: String) -> String {
        // remove wordpiece prefix and clean for searching
        var cleaned = token
        if cleaned.hasPrefix("##") {
            cleaned = String(cleaned.dropFirst(2))
        }
        return cleaned
    }

}


