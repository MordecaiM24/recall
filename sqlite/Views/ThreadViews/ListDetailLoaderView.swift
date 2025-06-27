//
//  ListDetailLoaderView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/26/25.
//

import SwiftUI

struct SwiftDetailLoaderView: View {
    @EnvironmentObject var contentService: ContentService
    @State private var isLoading = true
    @State private var error: Error?
    @State private var items: [Item] = []
    
    private var itemIds: [String] = []
    

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading thread...")
            } else if let error = error {
                Text("Error: \(error.localizedDescription)")
                    .foregroundColor(.red)
            } else {
                switch items[0].type {
                case .email:
                    if let emails = items.compactMap({ Email(from: $0) }) as? [Email] {
                        EmailThreadView(emails: emails)
                    } else {
                        Text("Error: Could not load emails.")
                    }
                case .message:
                    if let messages = items.compactMap({ Message(from: $0) }) as? [Message] {
                        MessageThreadView(initialMessages: messages)
                    } else {
                        Text("Error: Could not load messages.")
                    }
                case .note:
                    if let note = items.first {
                        ItemDetailLoaderView(itemId: note.id, itemType: .note)
                    }
                case .document:
                    if let note = items.first {
                        ItemDetailLoaderView(itemId: note.id, itemType: .note)
                    }
                }
            }
        }
        .task {
            await loadThreadItems()
        }
    }

    private func loadThreadItems() async {
        isLoading = true
        do {
            items = try contentService.batch(ids: itemIds)
        } catch {
            self.error = error
        }
        isLoading = false
    }
}
