//
//  sqliteApp.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 5/25/25.
//

import SwiftUI

@main
struct ContentApp: App {
    @StateObject private var contentService = AsyncContentServiceLoader()
    
    var body: some Scene {
        WindowGroup {
            if contentService.isLoaded {
                MainTabView()
                    .environmentObject(contentService.service!)
            } else {
                LoadingView()
            }
        }
    }
}

class AsyncContentServiceLoader: ObservableObject {
    @Published var isLoaded = false
    @Published var service: ContentService?
    
    init() {
        Task {
            let contentService = try await withCheckedThrowingContinuation { continuation in
                Task.detached {
                    do {
                        let service = try ContentService()
                        continuation.resume(returning: service)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            await MainActor.run {
                self.service = contentService
                self.isLoaded = true
            }
        }
    }
}

struct LoadingView: View {
    var body: some View {
        Image(systemName: "books.vertical.circle")
            .font(.system(size: 192))
    }
}
