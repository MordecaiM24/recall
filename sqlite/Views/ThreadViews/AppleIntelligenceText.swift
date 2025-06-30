//
//  DemoView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/30/25.
//

import SwiftUI

struct DemoView: View {
    var body: some View {
        AppleIntelligenceText(text: "Apple Intelligence")
    }
}

struct AppleIntelligenceText: View {
    let text: String
    let font: Font = .system(size: 16)
    @State private var animate = false
    
    let gradientColors: [Color] = [
        .yellow.opacity(0.1), .mint.opacity(0.2), .yellow.opacity(0.1),
        .purple, .orange, .pink, .purple, .cyan, .purple, .pink, .orange,
        .yellow.opacity(0.1), .mint.opacity(0.9), .yellow.opacity(0.1)
    ]
    
    
    var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(.clear)
            .fixedSize()
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: gradientColors),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(
                    width: UIScreen.main.bounds.width * 3,
                    height: 20 // would need to change if any of the loading views were >1 line
                )
                .offset(x: animate
                        ? -UIScreen.main.bounds.width * 1.5
                        :  UIScreen.main.bounds.width * 1.5
                       )
                .animation(
                    .linear(duration: 7)
                    .repeatForever(autoreverses: false),
                    value: animate
                )
                .onAppear { animate = true }
                    .mask(
                        Text(text)
                            .font(font)
                    )
            )
    }
}

#Preview {
    DemoView()
}
