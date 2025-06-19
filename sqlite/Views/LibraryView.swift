//
//  LibraryView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var contentService: ContentService
    @State private var selectedContentType: ContentType? = nil
    @State private var sortOption: SortOption = .dateDescending
    @State private var searchText = ""
    @State private var allContent: [UnifiedContent] = []
    @State private var isLoading = true
    @State private var selection = Set<UUID>()
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.editMode) private var editMode
    
    enum SortOption: String, CaseIterable {
        case dateDescending = "Date (Newest)"
        case dateAscending = "Date (Oldest)"
        case titleAscending = "Title (A-Z)"
        case titleDescending = "Title (Z-A)"
        case typeAscending = "Type"
    }
    
    var filteredAndSortedContent: [UnifiedContent] {
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
                    
                    // filters
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            // content type filter
                            Button(action: { selectedContentType = nil }) {
                                Text("All")
                                    .font(.caption)
                                    .fontWeight(.medium)
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
                
                // content list
                if isLoading {
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
//                    LibraryContentList(content: filteredAndSortedContent)
                    List(selection: $selection) {
                        ForEach(filteredAndSortedContent) { item in
                            LibraryItemRow(content: item, reload: loadContent)
                        }
                    }.listStyle(.plain)
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: loadContent) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onTapGesture {
                isTextFieldFocused = false
            }
        }
        .onAppear {
            loadContent()
        }
    }
    
    func loadContent() {
        isLoading = true
        
        Task {
            let results = await contentService.getAllContent()
            
            await MainActor.run {
                var combinedContent = results
                
                allContent = combinedContent
                isLoading = false
            }
        }
    }
}

struct LibraryItemRow: View {
    let content: UnifiedContent
    let reload: () -> Void
    @EnvironmentObject var contentService: ContentService
    @State private var showingDetail = false
    @Environment(\.editMode) private var editMode
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 8) {
                Image(systemName: content.typeIcon).font(.title)
                Text(content.type.displayName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 60)
            
            VStack(alignment: .leading) {
                Text(content.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                Text(content.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                
                Text(content.formattedDate)
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
            ContentDetailView(content: content)
        }
        .swipeActions {
            Button(role: .destructive) {
                Task {
                    try? await contentService.deleteContent(
                        type: content.type,
                        id: content.id
                    )
                    
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
    let content: [UnifiedContent]
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(content) { item in
                    LibraryItemCard(content: item)
                }
            }
            .padding()
        }
    }
}

struct LibraryItemCard: View {
    let content: UnifiedContent
    @State private var showingDetail = false
    
    var body: some View {
        Button(action: { showingDetail = true }) {
            HStack(spacing: 12) {
                // type indicator
                VStack {
                    Image(systemName: content.typeIcon)
                        .font(.title3)
                    
                    Text(content.type.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: 60)
                
                // content info
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    
                    Text(content.snippet)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    
                    Text(content.formattedDate)
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
            ContentDetailView(content: content)
        }
    }
}

