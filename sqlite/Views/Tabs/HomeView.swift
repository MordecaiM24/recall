//
//  HomeView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import SwiftUI
import FoundationModels

struct ChatMessage: Identifiable {
    enum Status {
        case sending
        case searching
        case pullingThread
        case generating
        case complete
        case error
    }
    
    let id = UUID()
    var content: String
    let isUser: Bool
    let timestamp: Date
    var sources: [SearchResult]?
    var status: Status
    var toolCalls: [String] = []
    
    init(content: String, isUser: Bool, sources: [SearchResult]? = nil, status: Status = .complete) {
        self.content = content
        self.isUser = isUser
        self.timestamp = Date()
        self.sources = sources
        self.status = status
    }
}

struct HomeView: View {
    @EnvironmentObject var contentService: ContentService
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @FocusState private var isTextFieldFocused: Bool
    
    @State private var semanticSearchTool: SemanticSearchTool?
    @State private var getFullThreadTool: GetFullThreadTool?
    
    @State private var session: LanguageModelSession?
    
    private let model = SystemLanguageModel.default
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                switch model.availability {
                case .available:
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                if messages.isEmpty {
                                    EmptyStateView()
                                }
                                ForEach(messages) { message in
                                    ChatBubbleView(message: message)
                                        .id(message.id)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 20)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: messages.count, initial: false, { _, _ in
                            if let last = messages.last {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        })
                    }
                    
                    // input area
                    VStack(spacing: 0) {
                        Divider()
                        
                        HStack(spacing: 12) {
                            TextField("Ask anything", text: $inputText)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color(.systemGray6))
                                .cornerRadius(20)
                                .lineLimit(1...4)
                                .focused($isTextFieldFocused)
                            
                            Button(action: sendMessage) {
                                Image(systemName: isLoading ? "stop.circle.fill" : "arrow.up.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .blue)
                            }
                            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    }
                    .background(Color(.systemBackground))
                case .unavailable(.deviceNotEligible):
                    Text("Foundation models not available on this device")
                        .foregroundColor(.red)
                case .unavailable(.appleIntelligenceNotEnabled):
                    Text("Apple Intelligence not enabled. Enable in system settings")
                        .foregroundColor(.orange)
                case .unavailable(.modelNotReady):
                    Text("Foundation model not ready. Try again later")
                        .foregroundColor(.yellow)
                case .unavailable(let other):
                    Text("Foundation model unavailable: \(other)")
                        .foregroundColor(.red)
                }
            }
            .navigationTitle("Recall")
            .navigationBarTitleDisplayMode(.inline)
            .onTapGesture { isTextFieldFocused = false }
            .task {
                setupSession()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // clear messages and reinitialize session
                        // probably want to make this make a "real" session but that's a problem for a real app.
                        messages = []
                        setupSession()
                        inputText = ""
                        session?.prewarm()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
    
    private func setupSession() {
        // initialize tools
        semanticSearchTool = SemanticSearchTool(contentService: contentService)
        getFullThreadTool = GetFullThreadTool(contentService: contentService)
        
        guard let searchTool = semanticSearchTool,
              let threadTool = getFullThreadTool else { return }
        
        // create session with tools
        session = LanguageModelSession(
            tools: [searchTool, threadTool],
            instructions: Instructions {
                "You are a helpful assistant that can search through personal content including emails, messages, documents, and notes. Use this capability as often as possible."
                
                "Use semanticSearch to find content based on meaning and context. use getFullThread to show complete conversations."
                
                "When search results suggest viewing a full thread, automatically use getFullThread to provide complete context."
                
                "Semantic search *will not* bring up full threads. Order your tool calls accordingly. When not sure, use semantic search to first find results, then chain that with getFullThread to ensure you get the most relevant context."
            }
        )
        
        // prewarm the session
        session?.prewarm()
        print("session prewarmed with tools")
    }
    
    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let session = session else { return }
        
        let userMsg = ChatMessage(content: trimmed, isUser: true, status: .sending)
        messages.append(userMsg)
        
        // default placeholder assistant message
        let assistantMsg = ChatMessage(content: "Searching...", isUser: false, status: .searching)
        messages.append(assistantMsg)
        
        inputText = ""
        isTextFieldFocused = false
        isLoading = true
        
        Task {
            do {
                // setup tool callbacks
                if let searchTool = semanticSearchTool {
                    searchTool.onSearchStart = { query in
                        await MainActor.run {
                            if let idx = messages.firstIndex(where: { $0.id == assistantMsg.id }) {
                                messages[idx].content = "Searching for '\(query)'..."
                                messages[idx].status = .searching
                            }
                        }
                    }
                    
                    searchTool.onSearchResults = {query, results in
                        await MainActor.run {
                            if let idx = messages.firstIndex(where: { $0.id == assistantMsg.id }) {
                                messages[idx].sources = results
                                messages[idx].toolCalls.append("semanticSearch")
                                if results.isEmpty {
                                    messages[idx].content = "I couldn't find any content related to '\(query)'. Try adding some documents, messages, emails, or notes first."
                                    messages[idx].status = .complete
                                } else {
                                    messages[idx].content = "Found \(results.count) results. Analyzing..."
                                    messages[idx].status = .generating
                                }
                            }
                        }
                    }
                }
                
                if let threadTool = getFullThreadTool {
                    threadTool.onThreadStart = { threadId in
                        await MainActor.run {
                            if let idx = messages.firstIndex(where: { $0.id == assistantMsg.id }) {
                                messages[idx].content = "Pulling full thread..."
                                messages[idx].status = .pullingThread
                                messages[idx].toolCalls.append("getFullThread")
                            }
                        }
                    }
                    
                    threadTool.onThreadComplete = { threadId, items in
                        await MainActor.run {
                            if let idx = messages.firstIndex(where: { $0.id == assistantMsg.id }) {
                                let itemsText = items.isEmpty ? "No items" : "\(items.count) items"
                                messages[idx].content = "Got thread with \(itemsText). Generating response..."
                                messages[idx].status = .generating
                            }
                        }
                    }
                }
                
                let response = try await session.respond(to: trimmed)
                
                await MainActor.run {
                    if let idx = messages.firstIndex(where: { $0.id == assistantMsg.id }) {
                        messages[idx].content = response.content
                        messages[idx].status = .complete
                        isLoading = false
                    }
                }
                
            } catch {
                await MainActor.run {
                    if let idx = messages.firstIndex(where: { $0.id == assistantMsg.id }) {
                        messages[idx].content = "Sorry, i ran into an error. Please try again."
                        messages[idx].status = .error
                        isLoading = false
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            VStack(spacing: 8) {
                Text("Ask about your content")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Search through your documents, messages, emails, and notes using natural language.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Try asking:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                SampleQuestionView(text: "What did alice say about the project?")
                SampleQuestionView(text: "Show me my emails about that machine learning conference")
                SampleQuestionView(text: "Who is the lead developer on this project?")
            }
        }
        .padding(.top, 40)
        .padding(.horizontal)
    }
}

struct SampleQuestionView: View {
    let text: String
    
    var body: some View {
        Text("• \(text)")
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChatBubbleView: View {
    let message: ChatMessage
    @State private var showingSources = false
    @State private var ellipsis = ""
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var statusText: String {
        switch message.status {
        case .searching: return "Searching"
        case .pullingThread: return "Pulling thread"
        case .generating: return "Generating"
        default: return ""
        }
    }
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 50)
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                Text(message.content + (message.status == .searching || message.status == .generating || message.status == .pullingThread ? ellipsis : ""))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(message.isUser ? Color.blue : Color(.systemGray5))
                    .foregroundColor(message.isUser ? .white : .primary)
                    .cornerRadius(18)
                
                // show tool usage indicators
                if !message.toolCalls.isEmpty && (message.status == .complete || message.status == .generating || message.status == .pullingThread) {
                    HStack(spacing: 8) {
                        ForEach(message.toolCalls, id: \.self) { tool in
                            HStack(spacing: 4) {
                                Image(systemName: tool == "semanticSearch" ? "magnifyingglass" : "doc.on.doc")
                                    .font(.caption2)
                                Text(tool == "semanticSearch" ? "Searched" : "Pulled thread")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                        }
                    }
                }
                
                // sources section
                if let sources = message.sources, !sources.isEmpty, (message.status == .complete || message.status == .generating) {
                    Button(action: { showingSources.toggle() }) {
                        HStack(spacing: 6) {
                            Image(systemName: showingSources ? "chevron.down" : "chevron.right")
                                .font(.caption)
                            Text("\(sources.count) source\(sources.count == 1 ? "" : "s")")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    if showingSources {
                        LazyVStack(spacing: 8) {
                            ForEach(sources) { source in
                                SourceCardView(searchResult: source)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if !message.isUser {
                Spacer(minLength: 50)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showingSources)
        .onReceive(timer) { _ in
            if message.status == .searching || message.status == .generating || message.status == .pullingThread {
                ellipsis = (ellipsis == "..." ? "" : ellipsis + ".")
            } else {
                ellipsis = ""
            }
        }
    }
}

// MARK: - Observable Tool Wrappers

final class ObservableSemanticSearchTool: Tool {
    let name = "semanticSearch"
    let description = "Search through documents, emails, messages, and notes using semantic similarity. Finds content based on meaning, not just keywords."
    
    private let wrappedTool: SemanticSearchTool
    private let contentService: ContentService
    var onSearch: (([SearchResult]) async -> Void)?
    
    init(contentService: ContentService) {
        self.contentService = contentService
        self.wrappedTool = SemanticSearchTool(contentService: contentService)
    }
    
    @Generable
    struct Arguments {
        @Guide(description: "Natural language query to search for based on meaning and context")
        let query: String
        
        @Guide(description: "Maximum number of results to return, between 1 and 10")
        let limit: Int
    }
    
    func call(arguments: Arguments) async throws -> ToolOutput {
        // perform actual search to get results for callback
        let results = try await contentService.search(arguments.query, limit: arguments.limit)
        await onSearch?(results)
        
        // forward to wrapped tool
        let wrappedArgs = SemanticSearchTool.Arguments(query: arguments.query, limit: arguments.limit)
        return try await wrappedTool.call(arguments: wrappedArgs)
    }
}

final class ObservableGetFullThreadTool: Tool {
    let name = "getFullThread"
    let description = "Get the complete conversation thread for an email chain or message conversation. Shows full context."
    
    private let wrappedTool: GetFullThreadTool
    var onThreadPull: ((String) async -> Void)?
    
    init(contentService: ContentService) {
        self.wrappedTool = GetFullThreadTool(contentService: contentService)
    }
    
    @Generable
    struct Arguments {
        @Guide(description: "The thread id to retrieve the full conversation for")
        let threadId: String
        
        @Guide(description: "The amount of items in the conversation to find")
        let itemCount: Int
    }
    
    func call(arguments: Arguments) async throws -> ToolOutput {
        await onThreadPull?(arguments.threadId)
        
        // forward to wrapped tool
        let wrappedArgs = GetFullThreadTool.Arguments(threadId: arguments.threadId, itemCount: arguments.itemCount)
        return try await wrappedTool.call(arguments: wrappedArgs)
    }
}

struct SourceCardView: View {
    let searchResult: SearchResult
    @State private var showingDetail = false
    
    var body: some View {
        Button(action: { showingDetail = true }) {
            HStack(spacing: 12) {
                Image(systemName: searchResult.thread.type.icon)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(searchResult.thread.snippet)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    HStack {
                        Text(searchResult.thread.created, style: .date)
                            .font(.caption2)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            ContentDetailView(item: searchResult.items.first!)
        }
    }
}

#Preview {
    HomeView()
}
