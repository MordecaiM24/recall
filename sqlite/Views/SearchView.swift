//
//  SearchView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import SwiftUI

struct SearchView: View {
    @EnvironmentObject var contentService: ContentService
    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var selectedContentTypes: Set<ContentType> = Set(ContentType.allCases)
    @State private var isLoading = false
    @State private var showingFilters = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // search bar and filters
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        TextField("search your content...", text: $searchText)
                            .textFieldStyle(.plain)
                            .onSubmit {
                                performSearch()
                            }
                        
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Button(action: { showingFilters.toggle() }) {
                            Image(systemName: showingFilters ? "line.horizontal.3.decrease.circle.fill" : "line.horizontal.3.decrease.circle")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    if showingFilters {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(ContentType.allCases, id: \.self) { type in
                                    FilterChipView(
                                        type: type,
                                        isSelected: selectedContentTypes.contains(type)
                                    ) {
                                        if selectedContentTypes.contains(type) {
                                            selectedContentTypes.remove(type)
                                        } else {
                                            selectedContentTypes.insert(type)
                                        }
                                        if !searchText.isEmpty {
                                            performSearch()
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                
                Divider()
                
                // results
                if isLoading {
                    VStack(spacing: 16) {
                        Spacer()
                        ProgressView()
                        Text("searching...")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else if searchText.isEmpty {
                    EmptySearchView()
                } else if searchResults.isEmpty {
                    NoResultsView(searchText: searchText)
                } else {
                    SearchResultsList(results: searchResults)
                }
            }
            .navigationTitle("search")
            .navigationBarTitleDisplayMode(.inline)
        }
        .animation(.easeInOut(duration: 0.2), value: showingFilters)
//        .onChange(of: searchText) { newValue in
//            if newValue.isEmpty {
//                searchResults = []
//            }
//        }
    }
    
    private func performSearch() {
        let trimmedText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            searchResults = []
            return
        }
        
        isLoading = true
        
        Task {
            do {
                let results = try await contentService.search(trimmedText, limit: 50)
                print(results)
                await MainActor.run {
                    searchResults = results
                    isLoading = false
                }
            } catch {
                print("Error searching: \(error)")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
}

struct FilterChipView: View {
    let type: ContentType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.caption)
                Text(type.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

struct EmptySearchView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("Search your knowledge base")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Find documents, messages, emails, and notes using keywords or natural language")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .padding()
    }
}

struct NoResultsView: View {
    let searchText: String
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("no results found")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("couldn't find anything for '\(searchText)'")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Text("try different keywords or add more content")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding()
    }
}

struct SearchResultsList: View {
    let results: [SearchResult]
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(results) { result in
                    SearchResultCard(searchResult: result)
                }
            }
            .padding()
        }
    }
}

struct SearchResultCard: View {
    let searchResult: SearchResult
    @State private var showingDetail = false
    
    var body: some View {
        Button(action: { showingDetail = true }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: searchResult.thread.type.icon)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(searchResult.thread.type.displayName)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                            
                            Text(searchResult.thread.created, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                
                Text(searchResult.thread.snippet)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            ContentDetailView(item: searchResult.items.first!)
        }
    }
}
