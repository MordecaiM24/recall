//
//  HomeView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import SwiftUI

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
                                        Text("ask about your content")
                                            .font(.title2)
                                            .fontWeight(.semibold)
                                        
                                        Text("search through your documents, messages, emails, and notes using natural language")
                                            .font(.body)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("try asking:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        SampleQuestionView(text: "what did alice say about the project?")
                                        SampleQuestionView(text: "show me emails about machine learning")
                                        SampleQuestionView(text: "find notes from last week")
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
                        TextField("ask about your content...", text: $inputText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray6))
                            .cornerRadius(20)
                            .lineLimit(1...4)
                        
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
            .navigationTitle("knowledge base")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func sendMessage() {
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }
        
        // add user message
        let userMessage = ChatMessage(content: trimmedInput, isUser: true)
        messages.append(userMessage)
        
        // clear input
        inputText = ""
        isLoading = true
        
        // simulate ai response with search
        Task {
            let searchResults = await contentService.search(query: trimmedInput, limit: 5)
            
            await MainActor.run {
                let responseContent: String
                let sources: [UnifiedContent]?
                
                if searchResults.isEmpty {
                    responseContent = "i couldn't find any content related to '\(trimmedInput)'. try adding some documents, messages, emails, or notes first."
                    sources = nil
                } else {
                    responseContent = "i found \(searchResults.count) relevant items about '\(trimmedInput)'. here's what i discovered:"
                    sources = searchResults
                }
                
                let assistantMessage = ChatMessage(content: responseContent, isUser: false, sources: sources)
                messages.append(assistantMessage)
                isLoading = false
            }
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
                Text(content.typeIcon)
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

