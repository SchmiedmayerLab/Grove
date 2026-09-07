//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI
#if Textual
import Textual
#endif


/// Keeps the whole conversation to a single text selection.
///
/// Without it every message coordinates only its own paragraphs, and a selection in one stays put while the reader
/// selects in another.
@available(iOS 18, macOS 15, watchOS 11, *)
struct SingleTextSelection: ViewModifier {
    func body(content: Content) -> some View {
        #if Textual
        content.textual.textSelectionCoordination()
        #else
        content
        #endif
    }
}


/// Lets the reader select a message's text, whichever way the message is rendered.
///
/// With Textual, the selection menu also offers to ask a follow-up question about the selected passage
/// whenever ``ChatMessageActions/followUp`` is enabled.
@available(iOS 18, macOS 15, watchOS 11, *)
struct SelectableMessageText: ViewModifier {
    @Environment(\.chatMessageActions) private var enabledActions
    @Environment(ChatFollowUp.self) private var followUp: ChatFollowUp?

    #if Textual
    private var selectionActions: [TextSelectionAction] {
        guard enabledActions.contains(.followUp), let followUp else {
            return []
        }
        return [
            TextSelectionAction(
                title: String(localized: "Ask a Follow-Up Question", bundle: .module),
                systemImage: "quote.bubble"
            ) { selectedText in
                followUp.quote(selectedText)
            }
        ]
    }
    #endif

    func body(content: Content) -> some View {
        #if Textual
        content
            .textual.textSelection(.enabled)
            .textual.textSelectionActions(selectionActions)
        #else
        content.textSelection(.enabled)
        #endif
    }
}
