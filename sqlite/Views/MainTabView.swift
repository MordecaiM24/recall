//
//  MainTabView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Image(systemName: "bubble.left.and.bubble.right")
                    Text("Chat")
                }
            
            SearchView()
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("Search")
                }
            
            LibraryView()
                .tabItem {
                    Image(systemName: "folder")
                    Text("Library")
                }
            
            AddContentView()
                .tabItem {
                    Image(systemName: "plus.circle")
                    Text("Import")
                }
            
            
        }
        .accentColor(.blue)
    }
}
