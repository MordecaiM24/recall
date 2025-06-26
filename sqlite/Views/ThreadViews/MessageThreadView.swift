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
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.isFromMe {
                Spacer(minLength: 60)
                messageBubble
            } else {
                messageBubble
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 1)
    }
    
    private var messageBubble: some View {
        Text(message.text)
            .font(.system(size: 16))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundColor(message.isFromMe ? .white : .primary)
            .background(bubbleShape)
            .fixedSize(horizontal: false, vertical: true)
    }
    
    private var bubbleShape: some View {
        BubbleShape(
            isFromMe: message.isFromMe,
            hastail: isLastInGroup
        )
        .fill(message.isFromMe ?
              LinearGradient(colors: [Color(red: 0.05, green: 0.55, blue: 1.0),
                                    Color(red: 0.0, green: 0.48, blue: 0.99)],
                           startPoint: .topLeading, endPoint: .bottomTrailing) :
              LinearGradient(colors: [Color(.systemGray5), Color(.systemGray6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }
}

struct BubbleShape: Shape {
    let isFromMe: Bool
    let hastail: Bool
    
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let tailSize: CGFloat = 6
        
        var path = Path()
        
        if isFromMe {
            // right-aligned bubble with tail on bottom right
            path.move(to: CGPoint(x: radius, y: 0))
            path.addLine(to: CGPoint(x: rect.width - radius, y: 0))
            path.addQuadCurve(to: CGPoint(x: rect.width, y: radius),
                            control: CGPoint(x: rect.width, y: 0))
            
            if hastail {
                path.addLine(to: CGPoint(x: rect.width, y: rect.height - radius - tailSize))
                path.addQuadCurve(to: CGPoint(x: rect.width - radius, y: rect.height - tailSize),
                                control: CGPoint(x: rect.width, y: rect.height - tailSize))
                path.addLine(to: CGPoint(x: rect.width - radius + 2, y: rect.height - tailSize))
                path.addQuadCurve(to: CGPoint(x: rect.width + 2, y: rect.height + 2),
                                control: CGPoint(x: rect.width - 2, y: rect.height))
                path.addQuadCurve(to: CGPoint(x: rect.width - 8, y: rect.height - 2),
                                control: CGPoint(x: rect.width - 4, y: rect.height - 1))
                path.addLine(to: CGPoint(x: radius, y: rect.height - 2))
            } else {
                path.addLine(to: CGPoint(x: rect.width, y: rect.height - radius))
                path.addQuadCurve(to: CGPoint(x: rect.width - radius, y: rect.height),
                                control: CGPoint(x: rect.width, y: rect.height))
                path.addLine(to: CGPoint(x: radius, y: rect.height))
            }
            
            path.addQuadCurve(to: CGPoint(x: 0, y: rect.height - radius),
                            control: CGPoint(x: 0, y: rect.height))
            path.addLine(to: CGPoint(x: 0, y: radius))
            path.addQuadCurve(to: CGPoint(x: radius, y: 0),
                            control: CGPoint(x: 0, y: 0))
        } else {
            // left-aligned bubble with tail on bottom left
            path.move(to: CGPoint(x: rect.width - radius, y: 0))
            path.addQuadCurve(to: CGPoint(x: rect.width, y: radius),
                            control: CGPoint(x: rect.width, y: 0))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height - radius))
            path.addQuadCurve(to: CGPoint(x: rect.width - radius, y: rect.height),
                            control: CGPoint(x: rect.width, y: rect.height))
            
            if hastail {
                path.addLine(to: CGPoint(x: radius + tailSize, y: rect.height))
                path.addQuadCurve(to: CGPoint(x: radius, y: rect.height - tailSize),
                                control: CGPoint(x: radius, y: rect.height))
                path.addLine(to: CGPoint(x: radius - 2, y: rect.height - tailSize))
                path.addQuadCurve(to: CGPoint(x: -2, y: rect.height + 2),
                                control: CGPoint(x: 2, y: rect.height))
                path.addQuadCurve(to: CGPoint(x: 8, y: rect.height - 2),
                                control: CGPoint(x: 4, y: rect.height - 1))
                path.addLine(to: CGPoint(x: 8, y: rect.height - 2))
                path.addLine(to: CGPoint(x: 8, y: radius))
            } else {
                path.addLine(to: CGPoint(x: radius, y: rect.height))
                path.addQuadCurve(to: CGPoint(x: 0, y: rect.height - radius),
                                control: CGPoint(x: 0, y: rect.height))
                path.addLine(to: CGPoint(x: 0, y: radius))
            }
            
            path.addQuadCurve(to: CGPoint(x: radius, y: 0),
                            control: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: rect.width - radius, y: 0))
        }
        
        return path
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
    @State private var isLoadingMore = false
    
    init(initialMessages: [Message]) {
        self._messages = State(initialValue: initialMessages.sorted { $0.date < $1.date })
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if isLoadingMore {
                        ProgressView()
                            .padding()
                    }
                    
                    ForEach(groupedMessages, id: \.0) { date, dayMessages in
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
