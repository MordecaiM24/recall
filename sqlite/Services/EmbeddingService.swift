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
    
    private func convertTokensToIds(tokens: [String]) throws -> [Int] {
        if tokens.count > maxLen {
            throw TokenizerError.tooLong(
                "Token sequence length (\(tokens.count)) exceeds maximum length (\(maxLen))"
            )
        }
        return tokens.compactMap { vocab[$0] }
    }
    
    /// Main entry point for sentence transformer models
    func encode(text: String, maxLength: Int = 512) throws -> TokenizationResult {
        // Tokenize the text
        let tokens = tokenize(text: text)
        
        // Add special tokens: [CLS] + tokens + [SEP]
        let specialTokens = ["[CLS]"] + tokens + ["[SEP]"]
        
        // Convert to IDs
        let tokenIds = try convertTokensToIds(tokens: specialTokens)
        
        // Truncate if needed
        let truncatedIds = Array(tokenIds.prefix(maxLength))
        
        // Create attention mask (1 for real tokens, 0 for padding)
        let realTokenCount = truncatedIds.count
        let attentionMask = Array(repeating: 1, count: realTokenCount) +
                          Array(repeating: 0, count: maxLength - realTokenCount)
        
        // Pad input IDs to maxLength
        let paddedIds = truncatedIds + Array(repeating: 0, count: maxLength - realTokenCount)
        
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
