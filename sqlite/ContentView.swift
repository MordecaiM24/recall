//
//  ContentView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 5/25/25.
//
import SwiftUI

struct ContentView: View {
    @StateObject private var model = ContactModel()
    @State private var name = ""

    var body: some View {
        VStack(spacing: 16) { 
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Insert") {
                    guard !name.isEmpty else { return }
                    model.insert(name: name)
                    name = ""
                }
                Button("Refresh") {
                    model.refresh()
                }
            }
            List(model.contacts) { contact in
                Text(contact.name)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
