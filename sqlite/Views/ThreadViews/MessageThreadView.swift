//
//  MessageThreadView.swift
//  sqlite
//
//  Created by Mordecai Mengesteab on 6/26/25.
//

import SwiftUI

struct MessageBubble: View {
    let message: Message
    let isLastInGroup: Bool
    
    private let outgoingBubbleColor = Color(red: 0.03921568627, green: 0.5176470588, blue: 1)
    private let incomingBubbleColor = Color(red: 0.1490196078, green: 0.1490196078, blue: 0.1607843137)
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.isFromMe {
                Spacer(minLength: 60)
                outgoingBubble
            } else {
                incomingBubbleView
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 1)
    }
    
    private var outgoingBubble: some View {
        ZStack(alignment: .bottomTrailing) {
            if isLastInGroup {
                Image("outgoingTail")
                    .padding(EdgeInsets(top: 0, leading: 0, bottom: -2, trailing: -5))
            }
            Text(message.text)
                .font(.body)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(outgoingBubbleColor)
                )
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    private var incomingBubbleView: some View {
        ZStack(alignment: .bottomLeading) {
            if isLastInGroup {
                Image("incomingTail")
                    .padding(EdgeInsets(top: 0, leading: -5, bottom: -2, trailing: 0))
            }
            Text(message.text)
                .font(.body)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(incomingBubbleColor)
                )
        }
        .fixedSize(horizontal: false, vertical: true)
    }

}

struct DateSeparator: View {
    let date: Date
    
    var body: some View {
        HStack {
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(height: 0.5)
            
            Text(date, style: .date)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .background(Color(.systemBackground))
            
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(height: 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct MessageThreadView: View {
    @State private var messages: [Message]
    @Environment(\.dismiss) private var dismiss
    
    init(initialMessages: [Message]) {
        self._messages = State(initialValue: initialMessages.sorted { $0.date < $1.date })
    }
    
    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color(.systemGray3))
                .frame(width: 40, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .onTapGesture {
                    dismiss()
                }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groupedMessages.reversed(), id: \.0) { date, dayMessages in
                            DateSeparator(date: date)
                            
                            ForEach(Array(dayMessages.enumerated()), id: \.element.id) { index, message in
                                let isLastInGroup = isLastMessageInGroup(message: message, index: index, dayMessages: dayMessages)
                                
                                VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 2) {
                                    if !message.isFromMe && isFirstMessageInGroup(message: message, index: index, dayMessages: dayMessages) {
                                        HStack {
                                            Text(message.displayName)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .padding(.leading, 20)
                                            Spacer()
                                        }
                                    }
                                    
                                    MessageBubble(message: message, isLastInGroup: isLastInGroup)
                                    
                                    if isLastInGroup {
                                        HStack {
                                            if message.isFromMe {
                                                Spacer()
                                            }
                                            Text(message.date, style: .time)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .opacity(0.7)
                                                .padding(.horizontal, 20)
                                            if !message.isFromMe {
                                                Spacer()
                                            }
                                        }
                                        .padding(.bottom, 8)
                                    }
                                }
                                .id(message.id)
                            }
                        }
                    }
                }
            }
            .background(Color(.systemBackground))
        }
    }
    
    private var groupedMessages: [(Date, [Message])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: messages) { message in
            calendar.startOfDay(for: message.date)
        }
        return grouped.sorted { $0.key < $1.key }.map { ($0.key, $0.value.sorted { $0.date < $1.date }) }
    }
    
    private func isLastMessageInGroup(message: Message, index: Int, dayMessages: [Message]) -> Bool {
        if index == dayMessages.count - 1 { return true }
        let nextMessage = dayMessages[index + 1]
        return message.isFromMe != nextMessage.isFromMe ||
        message.date.timeIntervalSince(nextMessage.date) > 300 // 5min gap
    }
    
    private func isFirstMessageInGroup(message: Message, index: Int, dayMessages: [Message]) -> Bool {
        if index == 0 { return true }
        let previousMessage = dayMessages[index - 1]
        return message.isFromMe != previousMessage.isFromMe ||
        message.date.timeIntervalSince(previousMessage.date) > 300
    }
}
