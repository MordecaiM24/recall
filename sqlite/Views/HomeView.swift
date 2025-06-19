//
//  HomeView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import SwiftUI
import FoundationModels

struct ChatMessage: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp: Date
    let sources: [UnifiedContent]?
    
    init(content: String, isUser: Bool, sources: [UnifiedContent]? = nil) {
        self.content = content
        self.isUser = isUser
        self.timestamp = Date()
        self.sources = sources
    }
}

struct HomeView: View {
    @EnvironmentObject var contentService: ContentService
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @FocusState private var isTextFieldFocused: Bool
    
    private var lmSession = LanguageModelSession()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // chat messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if messages.isEmpty {
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
                                        
                                        SampleQuestionView(text: "What did Alice say about the project?")
                                        SampleQuestionView(text: "Show me my emails about that machine learning conference.")
                                        SampleQuestionView(text: "Who is the lead developer on this project?")
                                    }
                                }
                                .padding(.top, 40)
                                .padding(.horizontal)
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
                    .onChange(of: messages.count) { _ in
                        if let lastMessage = messages.last {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
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
            }
            .navigationTitle("Recall")
            .navigationBarTitleDisplayMode(.inline)
            .onTapGesture {
                isTextFieldFocused = false
            }
        }
    }
    
    private func sendMessage() {
        let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        
        messages.append(.init(content: query, isUser: true))
        inputText = ""
        isTextFieldFocused = false
        isLoading = true
        
        Task {
            let results = await contentService.search(query: query, limit: 5)
            
            // basic response
//            let baseContent: String
//            if results.isEmpty {
//                baseContent = "couldn't find any content for '\(query)'. add some docs or notes first."
//            } else {
//                baseContent = "found \(results.count) items for '\(query)':"
//            }
//            await MainActor.run {
//                messages.append(.init(content: baseContent, isUser: false, sources: results))
//            }
            
            // if there are results, run summarization & reranking
            if !results.isEmpty {
                // prepare text
                let combined = results.map { "\($0.displayTitle): \($0.snippet)" }.joined(separator: "\n")
                
                // summarization
                do {
                    let sumPrompt = "summarize the following items concisely:\n\(combined)"
                    let summary = try await lmSession.respond(to: sumPrompt)
                    await MainActor.run {
                        messages.append(.init(content: "summary: \(summary)", isUser: false))
                    }
                } catch {}
                
                // reranking
                do {
                    let rankPrompt = "rank these items by relevance to '\(query)', list titles in order:\n\(results.map{$0.displayTitle}.joined(separator: "\n"))"
                    let ranking = try await lmSession.respond(to: rankPrompt)
                    await MainActor.run {
                        messages.append(.init(content: "reranking:\n\(ranking)", isUser: false))
                    }
                } catch {}
            } else {
                do {
                    let sumPrompt = "write a message to the user saying that you couldn't find any info for them"
                    let summary = try await lmSession.respond(to: sumPrompt)
                    await MainActor.run {
                        messages.append(.init(content: "summary: \(summary)", isUser: false))
                    }
                } catch {}
            }
            
            await MainActor.run { isLoading = false }
        }
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
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 50)
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                Text(message.content)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(message.isUser ? Color.blue : Color(.systemGray5))
                    .foregroundColor(message.isUser ? .white : .primary)
                    .cornerRadius(18)
                
                if let sources = message.sources, !sources.isEmpty {
                    Button(action: { showingSources.toggle() }) {
                        HStack(spacing: 6) {
                            Image(systemName: showingSources ? "chevron.down" : "chevron.right")
                                .font(.caption)
                            Text("\(sources.count) sources")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    if showingSources {
                        LazyVStack(spacing: 8) {
                            ForEach(sources) { source in
                                SourceCardView(content: source)
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
    }
}

struct SourceCardView: View {
    let content: UnifiedContent
    @State private var showingDetail = false
    
    var body: some View {
        Button(action: { showingDetail = true }) {
            HStack(spacing: 12) {
                Image(systemName: content.typeIcon)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.leading)
                    
                    Text(content.snippet)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    HStack {
                        Text(content.formattedDate)
                            .font(.caption2)
                        
                        Spacer()
                        
                        Text(content.similarityPercentage)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
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
            ContentDetailView(content: content)
        }
    }
}


#Preview {
    HomeView()
}
