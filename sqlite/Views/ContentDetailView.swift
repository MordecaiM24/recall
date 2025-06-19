//
//  ContentDetailView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/17/25.
//

import SwiftUI

struct ContentDetailView: View {
    let content: UnifiedContent
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // header
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: content.typeIcon)
                                .font(.largeTitle)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(content.type.displayName)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                                
                                Text(content.formattedDate)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Relevance")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text(content.similarityPercentage)
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                            }
                        }
                        
                        Text(content.displayTitle)
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.leading)
                    }
                    
                    Divider()
                    
                    // metadata
                    if !content.metadata.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Details")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 2), spacing: 8) {
                                ForEach(Array(content.metadata.keys.sorted()), id: \.self) { key in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(key.capitalized)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        Text("\(content.metadata[key] ?? "")")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        
                        Divider()
                    }
                    
                    // content
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Content")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(content.content)
                            .font(.body)
                            .lineSpacing(4)
                            .multilineTextAlignment(.leading)
                    }
                    
                    Spacer(minLength: 50)
                }
                .padding()
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: shareContent) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
    
    private func shareContent() {
        let shareText = """
        \(content.displayTitle)
        
        \(content.content)
        
        Type: \(content.type.displayName)
        Date: \(content.formattedDate)
        Relevance: \(content.similarityPercentage)
        """
        
        let activityVC = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
    }
}


#Preview {
    ContentDetailView(content: UnifiedContent(id: "a", type: .document, title: "asdf", content: "asdf", snippet: "asdf", date: .now, distance: 0.0))
}
