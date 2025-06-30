//
//  LibraryView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var contentService: ContentService
    @State private var allItems: [Item] = []
    @State private var allThreads: [Thread] = []
    @State private var contentCounts: [ContentType: Int] = [:]
    @State private var selectedContentType: ContentType? = nil
    @State private var sortOption: SortOption = .dateDescending
    @State private var searchText = ""
    @FocusState private var isTextFieldFocused: Bool
    
    private let pageSize = 50
    
    enum SortOption: String, CaseIterable {
        case dateDescending = "Date (Newest)"
        case dateAscending = "Date (Oldest)"
        case titleAscending = "Title (A-Z)"
        case titleDescending = "Title (Z-A)"
        case typeAscending = "Type"
    }
    
    var filteredAndSortedContent: [Thread] {
        var content = allThreads
        
        // filter by content type
        if let selectedType = selectedContentType {
            content = content.filter { $0.type == selectedType }
        }
        
        // filter by search text. not a semantic search in this tab.
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            content = content.filter {
                $0.snippet.lowercased().contains(searchLower) ||
                $0.content.lowercased().contains(searchLower)
            }
        }
        
        // sort
        switch sortOption {
        case .dateDescending:
            content.sort { $0.created > $1.created }
        case .dateAscending:
            content.sort { $0.created < $1.created }
        case .titleAscending:
            content.sort { $0.snippet.lowercased() < $1.snippet.lowercased() }
        case .titleDescending:
            content.sort { $0.snippet.lowercased() > $1.snippet.lowercased() }
        case .typeAscending:
            content.sort { $0.type.rawValue < $1.type.rawValue }
        }
        
        return content
    }
    
    var body: some View {
        ZStack {
            NavigationView {
                VStack(spacing: 0) {
                    // filters and search
                    VStack(spacing: 12) {
                        // search bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            
                            TextField("Search library...", text: $searchText)
                                .textFieldStyle(.plain)
                                .focused($isTextFieldFocused)
                            
                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        
                        // filters with counts
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                // all content filter
                                Button(action: { selectedContentType = nil }) {
                                    HStack(spacing: 4) {
                                        Text("All")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedContentType == nil ? Color.blue : Color(.systemGray5))
                                    .foregroundColor(selectedContentType == nil ? .white : .primary)
                                    .cornerRadius(16)
                                }
                                .buttonStyle(.plain)
                                
                                ForEach(ContentType.allCases, id: \.self) { type in
                                    Button(action: { selectedContentType = type }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: type.icon)
                                                .font(.caption)
                                            Text(type.displayName)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                            
                                            if let count = contentCounts[type], count > 0 {
                                                Text("(\(count))")
                                                    .font(.caption2)
                                                    .opacity(0.7)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(selectedContentType == type ? Color.blue : Color(.systemGray5))
                                        .foregroundColor(selectedContentType == type ? .white : .primary)
                                        .cornerRadius(16)
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                Divider()
                                    .frame(height: 20)
                                
                                // sort picker
                                Menu {
                                    ForEach(SortOption.allCases, id: \.self) { option in
                                        Button(action: { sortOption = option }) {
                                            HStack {
                                                Text(option.rawValue)
                                                if sortOption == option {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.up.arrow.down")
                                            .font(.caption)
                                        Text(sortOption.rawValue)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color(.systemGray5))
                                    .foregroundColor(.primary)
                                    .cornerRadius(16)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    
                    Divider()
                    
                    // content list with pagination
                    if contentService.isLoading && allThreads.isEmpty {
                        VStack(spacing: 16) {
                            Spacer()
                            ProgressView()
                            Text("loading library...")
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    } else if allThreads.isEmpty {
                        EmptyLibraryView()
                    } else if filteredAndSortedContent.isEmpty {
                        NoResultsLibraryView(hasFilters: selectedContentType != nil || !searchText.isEmpty)
                    } else {
                        PaginatedLibraryContentList(
                            content: filteredAndSortedContent
                        )
                    }
                }
                .navigationTitle("Library")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { refresh() }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(contentService.isLoading)
                    }
                }
                
                .refreshable {
                    refresh()
                }
            }
        }
        .onTapGesture {
            isTextFieldFocused = false
        }
        .task {
            await initialLoad()
        }
        .onReceive(contentService.$isLoading) { _ in
            if !contentService.isLoading {
                refresh()
            }
        }
    }
    
    func initialLoad() async {
        guard !contentService.isLoading else { return }
        
        allThreads = []
        
        do {
            allThreads = try await contentService.getAllThreads()
        } catch {
            print("Error loading content: \(error)")
        }
    }
    
    func refresh() {
        Task {
            await initialLoad()
        }
    }
}

struct PaginatedLibraryContentList: View {
    let content: [Thread]
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(content.enumerated()), id: \.element.id) { index, thread in
                    LibraryItemCard(thread: thread)
                }
            }
            .padding()
        }
    }
}

struct ItemDetailLoaderView: View {
    let itemId: String
    let itemType: ContentType
    @EnvironmentObject var contentService: ContentService
    @State private var item: Item?
    
    var body: some View {
        VStack {
            if let item = item {
                ContentDetailView(item: item)
            } else {
                ProgressView()
                    .onAppear {
                        Task {
                            item = try? await contentService.one(itemType, id: itemId)
                        }
                    }
            }
        }
    }
}


struct LibraryItemRow: View {
    let item: Item
    let reload: () -> Void
    @EnvironmentObject var contentService: ContentService
    @State private var showingDetail = false
    @Environment(\.editMode) private var editMode
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 8) {
                Image(systemName: item.type.icon).font(.title)
                Text(item.type.displayName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 60)
            
            VStack(alignment: .leading) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                Text(item.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                
                Text(item.date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onTapGesture {
            guard editMode?.wrappedValue != .active else { return }
            showingDetail = true
        }
        .contentShape(Rectangle())
        .sheet(isPresented: $showingDetail) {
            ContentDetailView(item: item)
        }
        .swipeActions {
            Button(role: .destructive) {
                Task {
                    reload()
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct EmptyLibraryView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "folder")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("Library is empty")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Import some messages, emails, notes, or documents to get started")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .padding()
    }
}

struct NoResultsLibraryView: View {
    let hasFilters: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No matching content")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(hasFilters ? "Try adjusting your filters or search terms" : "No content matches your search")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .padding()
    }
}

struct LibraryContentList: View {
    let content: [Thread]
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(content) { thread in
                    LibraryItemCard(thread: thread)
                }
            }
            .padding()
        }
    }
}

struct LibraryItemCard: View {
    let thread: Thread
    @State private var showingDetail = false
    
    var body: some View {
        Button(action: { showingDetail = true }) {
            HStack(spacing: 12) {
                // type indicator
                VStack {
                    Image(systemName: thread.type.icon)
                        .font(.title3)
                    
                    Text(thread.type.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: 60)
                
                // content info
                VStack(alignment: .leading, spacing: 4) {
                    Text(thread.snippet)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    
                    Text(thread.content.prefix(100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    
                    Text(thread.created, style: .date)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            ThreadDetailLoaderView(thread: thread)
        }
    }
}

