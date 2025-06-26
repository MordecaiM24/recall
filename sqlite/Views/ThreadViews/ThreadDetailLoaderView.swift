
//
//  ThreadDetailLoaderView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/26/25.
//

import SwiftUI

struct ThreadDetailLoaderView: View {
    let thread: Thread
    @EnvironmentObject var contentService: ContentService
    @State private var isLoading = true
    @State private var items: [Item] = []
    @State private var error: Error?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading thread...")
            } else if let error = error {
                Text("Error: \(error.localizedDescription)")
                    .foregroundColor(.red)
            } else {
                switch thread.type {
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
                case .document, .note:
                    if let itemId = thread.itemIds.first {
                        ItemDetailLoaderView(itemId: itemId, itemType: thread.type)
                    } else {
                        Text("Error: Could not load item.")
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
            items = try await contentService.byThreadId(thread.id)
        } catch {
            self.error = error
        }
        isLoading = false
    }
}
