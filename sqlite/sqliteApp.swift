//
//  sqliteApp.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 5/25/25.
//

import SwiftUI

@main
struct ContentApp: App {
    @StateObject private var contentService: ContentService
    
    init() {
        do {
            let temp = try ContentService()
            _contentService = StateObject(wrappedValue: temp)
        } catch {
            fatalError("failed to initialize content service: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(contentService)
        }
    }
}

