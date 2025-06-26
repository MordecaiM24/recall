//
//  LibraryView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var contentService: ContentService
    @State private var allContent: [Item] = []
    @State private var isLoadingMore = false
    @State private var hasMoreContent = true
    @State private var contentCounts: [ContentType: Int] = [:]
    @State private var currentPage = 0
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
    
    var filteredAndSortedContent: [Item] {
        var content = allContent
        
        // filter by content type
        if let selectedType = selectedContentType {
            content = content.filter { $0.type == selectedType }
        }
        
        // filter by search text
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            content = content.filter {
                $0.title.lowercased().contains(searchLower) ||
                $0.content.lowercased().contains(searchLower)
            }
        }
        
        // sort
        switch sortOption {
        case .dateDescending:
            content.sort { $0.date > $1.date }
        case .dateAscending:
            content.sort { $0.date < $1.date }
        case .titleAscending:
            content.sort { $0.title.lowercased() < $1.title.lowercased() }
        case .titleDescending:
            content.sort { $0.title.lowercased() > $1.title.lowercased() }
        case .typeAscending:
            content.sort { $0.type.rawValue < $1.type.rawValue }
        }
        
        return content
    }
    
    var body: some View {
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
                if contentService.isLoading && allContent.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        ProgressView()
                        Text("loading library...")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else if allContent.isEmpty {
                    EmptyLibraryView()
                } else if filteredAndSortedContent.isEmpty {
                    NoResultsLibraryView(hasFilters: selectedContentType != nil || !searchText.isEmpty)
                } else {
                    PaginatedLibraryContentList(
                        content: filteredAndSortedContent,
                        isLoadingMore: isLoadingMore,
                        hasMore: hasMoreContent,
                        onLoadMore: { loadMoreIfNeeded() }
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
            .onTapGesture {
                isTextFieldFocused = false
            }
            .refreshable {
                refresh()
            }
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
        
        currentPage = 0
        allContent = []
        hasMoreContent = true
        
        do {
            let content = try await contentService.all(selectedContentType, limit: pageSize, offset: currentPage * pageSize)
            allContent = content
            hasMoreContent = content.count == pageSize
            currentPage += 1
        } catch {
            print("Error loading content: \(error)")
        }
    }
    
    func loadMoreIfNeeded() {
        guard !isLoadingMore && hasMoreContent else { return }
        
        Task {
            isLoadingMore = true
            
            do {
                let content = try await contentService.all(selectedContentType, limit: pageSize, offset: currentPage * pageSize)
                allContent.append(contentsOf: content)
                hasMoreContent = content.count == pageSize
                currentPage += 1
            } catch {
                print("Error loading more content: \(error)")
            }
            
            isLoadingMore = false
        }
    }
    
    func refresh() {
        Task {
            await initialLoad()
        }
    }
}

struct PaginatedLibraryContentList: View {
    let content: [Item]
    let isLoadingMore: Bool
    let hasMore: Bool
    let onLoadMore: () -> Void
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(content.enumerated()), id: \.element.id) { index, item in
                    LibraryItemCard(item: item)
                        .onAppear {
                            // trigger load more when we're near the end
                            if index >= content.count - 10 && hasMore && !isLoadingMore {
                                onLoadMore()
                            }
                        }
                }
                
                // loading indicator at bottom
                if isLoadingMore {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("loading more...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else if !hasMore && content.count > 0 {
                    Text("no more content")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .padding()
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
                    // try? await contentService.deleteContent(
                    //     type: content.type,
                    //     id: content.id
                    // )
                    
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
                Text("library is empty")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("import some messages, emails, notes, or documents to get started")
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
                Text("no matching content")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(hasFilters ? "try adjusting your filters or search terms" : "no content matches your search")
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
    let content: [Item]
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(content) { item in
                    LibraryItemCard(item: item)
                }
            }
            .padding()
        }
    }
}

struct LibraryItemCard: View {
    let item: Item
    @State private var showingDetail = false
    
    var body: some View {
        Button(action: { showingDetail = true }) {
            HStack(spacing: 12) {
                // type indicator
                VStack {
                    Image(systemName: item.type.icon)
                        .font(.title3)
                    
                    Text(item.type.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: 60)
                
                // content info
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    
                    Text(item.snippet)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    
                    Text(item.date, style: .date)
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
            ContentDetailView(item: item)
        }
    }
}

