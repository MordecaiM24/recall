//
//  Tools.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/27/25.
//

import Foundation
import FoundationModels
import SwiftUI

// MARK: - Observable Semantic Search Tool

@Observable
class SemanticSearchTool: Tool {
    let name = "semanticSearch"
    let description = "search through documents, emails, messages, and notes using semantic similarity. finds content based on meaning, not just keywords."
    
    private let contentService: ContentService
    
    @MainActor var searchHistory: [SearchQuery] = []
    
    // UI callback
    var onSearchResults: ((String, [SearchResult]) async -> Void)?
    var onSearchStart: ((String) async -> Void)?
    
    init(contentService: ContentService) {
        self.contentService = contentService
    }
    
    @Generable
    struct Arguments {
        @Guide(description: "natural language query to search for based on meaning and context")
        let query: String
        
        @Guide(description: "maximum number of results to return, between 1 and 10")
        let limit: Int
    }
    
    struct SearchQuery {
        let query: String
        let resultCount: Int
        let timestamp: Date
        
        init(query: String, resultCount: Int) {
            self.query = query
            self.resultCount = resultCount
            self.timestamp = Date()
        }
    }
    
    @MainActor
    private func recordSearch(query: String, resultCount: Int) {
        searchHistory.append(SearchQuery(query: query, resultCount: resultCount))
    }
    
    func call(arguments: Arguments) async throws -> ToolOutput {
        print("semantic search tool called with arguments: 'query: \(arguments.query)', limit: \(arguments.limit)")
        
        // notify UI that search is starting
        await onSearchStart?(arguments.query)
        
        do {
            let results = try await contentService.search(arguments.query, limit: arguments.limit)
            
            await recordSearch(query: arguments.query, resultCount: results.count)
            
            // notify UI with results
            await onSearchResults?(arguments.query, results)
            
            guard !results.isEmpty else {
                return ToolOutput("no results found for: '\(arguments.query)'")
            }
            
            print("found \(results.count) results")
            
            let summary = """
            search results for: "\(arguments.query)"
            found \(results.count) relevant \(results.count == 1 ? "item" : "items")
            
            """
            
            let formattedResults = results.enumerated().map { index, result in
                let thread = result.thread
                let relevantItem = result.items.first ?? result.items.last!
                let sender = extractSender(from: relevantItem)
                let timestamp = formatDate(relevantItem.date)
                
                return """
                [\(index + 1)]: \(thread.snippet)
                from: \(sender) - \(timestamp)
                content: \(relevantItem.content.prefix(150))\(relevantItem.content.count > 150 ? "..." : "")
                thread id: \(thread.id) (use getFullThread for complete conversation)
                """
            }.joined(separator: "\n\n")
            
            let suggestion = results.count == 1 ?
            "\n\nuse getFullThread to see the complete conversation?" : ""
            
            return ToolOutput(summary + formattedResults + suggestion)
            
        } catch {
            print("search error: \(error)")
            await onSearchResults?(arguments.query, [])
            return ToolOutput("error searching: \(error.localizedDescription)")
        }
    }
    
    private func extractSender(from item: Item) -> String {
        switch item.type {
        case .email:
            if let sender = item.metadata["sender"] as? String {
                return sender.components(separatedBy: "@").first?.capitalized ?? sender
            }
        case .message:
            if let contact = item.metadata["contact"] as? String {
                return contact
            }
        case .document:
            return "document"
        case .note:
            return "note"
        }
        return "unknown"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
            return "today \(formatter.string(from: date))"
        } else if Calendar.current.isDateInYesterday(date) {
            formatter.dateFormat = "h:mm a"
            return "yesterday \(formatter.string(from: date))"
        } else if Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.contains(date) == true {
            formatter.dateFormat = "EEEE h:mm a"
            return formatter.string(from: date)
        } else {
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Observable Get Full Thread Tool

@Observable
class GetFullThreadTool: Tool {
    let name = "getFullThread"
    let description = "get the complete conversation thread for an email chain or message conversation. shows full context."
    
    private let contentService: ContentService
    
    @MainActor var lookupHistory: [ThreadLookup] = []
    
    // UI callbacks
    var onThreadStart: ((String) async -> Void)?
    var onThreadComplete: ((String, [Item]) async -> Void)?
    
    init(contentService: ContentService) {
        self.contentService = contentService
    }
    
    @Generable
    struct Arguments {
        @Guide(description: "the thread id to retrieve the full conversation for")
        let threadId: String
        
        @Guide(description: "the amount of items in the conversation to find")
        let itemCount: Int
    }
    
    struct ThreadLookup {
        let threadId: String
        let timestamp: Date
        let itemCount: Int
        
        init(threadId: String, itemCount: Int) {
            self.threadId = threadId
            self.itemCount = itemCount
            self.timestamp = Date()
        }
    }
    
    @MainActor
    private func recordLookup(threadId: String, itemCount: Int) {
        lookupHistory.append(ThreadLookup(threadId: threadId, itemCount: itemCount))
    }
    
    func call(arguments: Arguments) async throws -> ToolOutput {
        print("get full thread tool called for thread id: '\(arguments.threadId)'")
        
        // notify UI that thread pull is starting
        await onThreadStart?(arguments.threadId)
        
        do {
            let items = try await contentService.byThreadId(arguments.threadId)
            await recordLookup(threadId: arguments.threadId, itemCount: items.count)
            
            // notify UI with thread items
            await onThreadComplete?(arguments.threadId, items)
            
            guard !items.isEmpty else {
                return ToolOutput("thread is empty or not found: '\(arguments.threadId)'")
            }
            
            let threadType = items.first?.type.rawValue ?? "unknown"
            let threadSummary = """
            thread contents (\(items.count) \(threadType)\(items.count == 1 ? "" : "s")):
            
            """
            
            let rawDump = items.map { item in
                let sender = extractSender(from: item)
                let timestamp = formatDate(item.date)
                
                return """
                --- \(timestamp) ---
                from: \(sender)
                \(item.title.isEmpty ? "" : "subject: \(item.title)\n")\(item.content)
                """
            }.joined(separator: "\n\n")
            
            return ToolOutput(threadSummary + rawDump)
        } catch {
            await onThreadComplete?(arguments.threadId, [])
            return ToolOutput("error retrieving thread: \(error.localizedDescription)")
        }
    }
    
    private func extractSender(from item: Item) -> String {
        switch item.type {
        case .email:
            if let sender = item.metadata["sender"] as? String {
                return sender
            }
        case .message:
            if let isFromMe = item.metadata["isFromMe"] as? Bool {
                return isFromMe ? "me" : (item.metadata["contact"] as? String ?? "them")
            }
        case .document, .note:
            return "document"
        }
        return "unknown"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
            return "today \(formatter.string(from: date))"
        } else if Calendar.current.isDateInYesterday(date) {
            formatter.dateFormat = "h:mm a"
            return "yesterday \(formatter.string(from: date))"
        } else if Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.contains(date) == true {
            formatter.dateFormat = "EEEE h:mm a"
            return formatter.string(from: date)
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Tool Output Extensions

extension ToolOutput {
    init(_ content: String) {
        self.init(GeneratedContent(content))
    }
}
