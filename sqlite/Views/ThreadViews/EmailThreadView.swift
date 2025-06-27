//
//  EmailThreadView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/26/25.
//

import SwiftUI

struct EmailThreadView: View {
    let emails: [Email]
    @State private var expandedEmails: Set<String> = []
    
    var sortedEmails: [Email] {
        emails.sorted { $0.date < $1.date }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // thread header
                VStack(alignment: .leading, spacing: 8) {
                    Text(emails.first?.subject ?? "")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.leading)
                    
                    HStack {
                        Text("\(emails.count) messages")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
                
                ForEach(Array(sortedEmails.enumerated()), id: \.element.id) { index, email in
                    EmailThreadRowView(
                        email: email,
                        isExpanded: expandedEmails.contains(email.id) || index == sortedEmails.count - 1,
                        isLast: index == sortedEmails.count - 1
                    ) {
                        toggleExpansion(for: email.id)
                    }
                }
            }
        }
        .onAppear {
            // expand the most recent email by default
            if let lastEmail = sortedEmails.last {
                expandedEmails.insert(lastEmail.id)
            }
        }
    }
    
    private func toggleExpansion(for emailId: String) {
        if expandedEmails.contains(emailId) {
            expandedEmails.remove(emailId)
        } else {
            expandedEmails.insert(emailId)
        }
    }
}

struct EmailThreadRowView: View {
    let email: Email
    let isExpanded: Bool
    let isLast: Bool
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 0) {
                    // header section
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(avatarColor)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Text(email.senderName.prefix(1).uppercased())
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(email.senderName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Text(formatDate(email.date))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                
                                if !isExpanded {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Text("to \(extractRecipientName(email.recipient))")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    
                    // content section
                    if isExpanded {
                        VStack(alignment: .leading, spacing: 12) {
                            if !email.snippet.isEmpty && email.snippet != email.content {
                                Text(email.snippet)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 16)
                            }
                            
                            Text(email.content)
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal, 16)
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                    } else {
                        // collapsed preview
                        Text(email.snippet.isEmpty ? email.preview : email.snippet)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            .padding(.bottom, 12)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .background(isLast ? Color(.systemBackground) : Color(.secondarySystemBackground))
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.bottom, isLast ? 16 : 8)
        }
    }
    
    private var avatarColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .red, .pink]
        let hash = abs(email.sender.hashValue)
        return colors[hash % colors.count]
    }
    
    private func extractRecipientName(_ recipient: String) -> String {
        if recipient.contains("<") {
            let components = recipient.components(separatedBy: "<")
            return components.first?.trimmingCharacters(in: .whitespaces) ?? recipient
        }
        return recipient
    }
    
    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "'Yesterday' h:mm a"
            return formatter.string(from: date)
        } else if calendar.dateInterval(of: .year, for: now)?.contains(date) == true {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy, h:mm a"
            return formatter.string(from: date)
        }
    }
}
