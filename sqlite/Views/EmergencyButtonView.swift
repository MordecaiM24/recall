//
//  EmergencyButtonView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/18/25.
//

import SwiftUI

struct EmergencyButtonView: View {
    @EnvironmentObject var contentService: ContentService
    
    var body: some View {
        Button("Nuke Database") {
            contentService.nukeDB()
        }
    }
}

#Preview {
    EmergencyButtonView()
}
