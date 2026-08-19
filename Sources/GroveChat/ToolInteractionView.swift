//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI

/// Displays a tool call, or the response to one, depending on the entity's ``ChatEntity/Role-swift.enum``.
@available(iOS 18, macOS 15, watchOS 11, *)
struct ToolInteractionView: View {
    let entity: ChatEntity

    @State private var isExpanded = false

    private var content: String {
        entity.content.text ?? ""
    }

    var body: some View {
        switch entity.role {
        case .assistant(.toolCall):
            row(symbolName: "function", accessibilityLabel: Text("FUNCTION_F_OF_X", bundle: .module)) {
                Text(content)
            }
        case .assistant(.toolResponse):
            row(symbolName: "equal", accessibilityLabel: Text("EQUAL_SIGN", bundle: .module)) {
                if content.contains(where: \.isNewline) && !isExpanded {
                    Text("SEE_MORE", bundle: .module)
                        .italic()
                } else {
                    Text(content)
                }
            }
        default:
            EmptyView()
        }
    }

    private func row(
        symbolName: String,
        accessibilityLabel: Text,
        @ViewBuilder label: () -> some View
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbolName)
                .accessibilityLabel(accessibilityLabel)
                .frame(width: 16)
            label()
                .lineLimit(isExpanded ? nil : 1)
                // The collapsed row truncates to keep the conversation readable; the label must not, or VoiceOver
                // reads half a tool call and stops.
                .accessibilityLabel(Text(content))
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .contentShape(.rect)
        .onTapGesture {
            withAnimation(.smooth(duration: 0.25)) {
                isExpanded.toggle()
            }
        }
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ToolInteractionView(entity: ChatEntity(role: .assistant(.toolCall), text: "get_weather(location: \"Stanford\")"))
        ToolInteractionView(entity: ChatEntity(role: .assistant(.toolResponse), text: "{\n  \"temperature\": 21\n}"))
    }
    .padding()
}
#endif
