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
    
    private let model = SystemLanguageModel.default
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                switch model.availability {
                case .available:
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
                case .unavailable(.deviceNotEligible):
                    Text("Foundation Models are not available on this device.")
                        .foregroundColor(.red)
                case .unavailable(.appleIntelligenceNotEnabled):
                    Text("Apple Intelligence is not enabled. Please enable it in System Settings.")
                        .foregroundColor(.orange)
                case .unavailable(.modelNotReady):
                    Text("Foundation Model is not ready yet. Please try again later.")
                        .foregroundColor(.yellow)
                case .unavailable(let other):
                    Text("Foundation Model is unavailable for an unknown reason: \(other)")
                        .foregroundColor(.red)
                }
            }
            .navigationTitle("Recall")
            .navigationBarTitleDisplayMode(.inline)
            .onTapGesture {
                isTextFieldFocused = false
            }
        }
    }
    
    private func sendMessage() {
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }

        let userMessage = ChatMessage(content: trimmedInput, isUser: true, status: .sending)
        messages.append(userMessage)

        var assistantMessage = ChatMessage(content: "Searching...", isUser: false, status: .searching)
        messages.append(assistantMessage)

        inputText = ""
        isTextFieldFocused = false
        isLoading = true

        Task {
            do {
                let searchResults = try await contentService.search(trimmedInput, limit: 5)

                await MainActor.run {
                    if let index = messages.firstIndex(where: { $0.id == assistantMessage.id }) {
                        messages[index].sources = searchResults
                        if searchResults.isEmpty {
                            messages[index].content = "I couldn't find any content related to '\(trimmedInput)'. Try adding some documents, messages, emails, or notes first."
                            messages[index].status = .complete
                            isLoading = false
                        } else {
                            messages[index].content = "Reading sources..."
                            messages[index].status = .generating
                        }
                    }
                }

                if !searchResults.isEmpty {
                    let session = LanguageModelSession()
                    let context = searchResults.map { $0.thread.snippet }.joined(separator: "\n")
                    let prompt = "Based on the following context, answer the question: \(trimmedInput)\n\nContext:\n\(context)"

                    let stream = session.streamResponse(
                        to: prompt,
                        generating: String.self,
                        options: GenerationOptions(sampling: .greedy)
                    )
                    
                    var streamedContent = ""
                    for try await partial in stream {
                        streamedContent = partial
                        await MainActor.run {
                            if let index = messages.firstIndex(where: { $0.id == assistantMessage.id }) {
                                messages[index].content = streamedContent
                                messages[index].status = .generating
                            }
                        }
                    }

                    await MainActor.run {
                        if let index = messages.firstIndex(where: { $0.id == assistantMessage.id }) {
                            messages[index].status = .complete
                            isLoading = false
                        }
                    }

                }
            } catch {
                await MainActor.run {
                    if let index = messages.firstIndex(where: { $0.id == assistantMessage.id }) {
                        messages[index].content = "Sorry, I ran into an error while searching or generating a response. Please try again."
                        messages[index].status = .error
                        isLoading = false
                    }
                }
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
    @State private var ellipsis = ""
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 50)
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                Text(message.content + (message.status == .searching || message.status == .generating ? ellipsis : ""))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(message.isUser ? Color.blue : Color(.systemGray5))
                    .foregroundColor(message.isUser ? .white : .primary)
                    .cornerRadius(18)
                
                if let sources = message.sources, !sources.isEmpty, (message.status == .complete || message.status == .generating) {
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
            if message.status == .searching || message.status == .generating {
                ellipsis = (ellipsis == "..." ? "" : ellipsis + ".")
            } else {
                ellipsis = ""
            }
        }
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
