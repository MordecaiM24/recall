//
//  ImportView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct AddContentView: View {
    @EnvironmentObject var contentService: ContentService
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // tab selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        TabSelectorButton(
                            title: "Document",
                            icon: "📄",
                            isSelected: selectedTab == 0
                        ) {
                            selectedTab = 0
                        }
                        
                        TabSelectorButton(
                            title: "Messages",
                            icon: "💬",
                            isSelected: selectedTab == 1
                        ) {
                            selectedTab = 1
                        }
                        
                        TabSelectorButton(
                            title: "Emails",
                            icon: "📧",
                            isSelected: selectedTab == 2
                        ) {
                            selectedTab = 2
                        }
                        
                        TabSelectorButton(
                            title: "Notes",
                            icon: "📝",
                            isSelected: selectedTab == 3
                        ) {
                            selectedTab = 3
                        }
                        
                        TabSelectorButton(
                            title: "Delete",
                            icon: "❌",
                            isSelected: selectedTab == 4
                        ) {
                            selectedTab = 4
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                
                // content forms
                TabView(selection: $selectedTab) {
                    AddDocumentView()
                        .tag(0)
                    
                    ImportMessagesView()
                        .tag(1)
                    
                    ImportEmailsView()
                        .tag(2)
                    
                    ImportNotesView()
                        .tag(3)
                    
                    Button("Delete All") {
                        contentService.clearAll()
                    }
                        .tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Import Your Content")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}


struct TabSelectorButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(icon)
                    .font(.title2)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(width: 80, height: 60)
            .background(isSelected ? Color.blue : Color.clear)
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

