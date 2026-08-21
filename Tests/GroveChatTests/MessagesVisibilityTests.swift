//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import GroveChat
import Testing


@Suite
struct MessagesVisibilityTests {
    private typealias Visibility = MessagesView.MessagesVisibility

    @Test
    func theDefaultShowsTheConversationAndHidesWhatAChatMarksHidden() {
        let visibility = Visibility.default

        #expect(!visibility.hides(ChatEntity(role: .user, text: "Hi")))
        #expect(!visibility.hides(ChatEntity(role: .assistant(.response), text: "Hello")))
        #expect(visibility.hides(ChatEntity(role: .hidden(type: .unknown), text: "System")))
        #expect(!visibility.hides(ChatEntity(role: .assistant(.toolCall), text: "call()")))
    }

    @Test
    func toolCallsAndThinkingAreHiddenOnlyWhenAsked() {
        let tidy = Visibility(hiddenMessages: .all, toolCalls: .hidden, thinking: .hidden)

        #expect(tidy.hides(ChatEntity(role: .assistant(.toolCall), text: "call()")))
        #expect(tidy.hides(ChatEntity(role: .assistant(.toolResponse), text: "{}")))
        #expect(tidy.hides(ChatEntity(role: .assistant(.thinking(startDate: nil, endDate: nil)), text: "…")))
        #expect(!tidy.hides(ChatEntity(role: .assistant(.response), text: "Hello")))
    }

    @Test
    func onlyTheNamedKindsOfHiddenMessageAreHidden() {
        let type = ChatEntity.HiddenMessageType(name: "conversationStarter")
        let visibility = Visibility(hiddenMessages: .custom([type]))

        #expect(visibility.hides(ChatEntity(role: .hidden(type: type), text: "Internal")))
        #expect(!visibility.hides(ChatEntity(role: .hidden(type: .unknown), text: "Other")))
    }

    /// The reason ``View/chatHiddenMessages(_:)`` exists: a chat's own opening input is a real user turn,
    /// so no role-based rule can tell it apart from something the participant wrote.
    @Test
    func aNamedMessageIsHiddenWhateverRoleItCarries() {
        let internalInput = ChatEntity(role: .user, text: "Follow the instructions to begin.")
        let participantInput = ChatEntity(role: .user, text: "Hi")
        let visibility = Visibility.default

        #expect(visibility.hides(internalInput, namedAsHidden: [internalInput.id]))
        #expect(!visibility.hides(participantInput, namedAsHidden: [internalInput.id]))
        #expect(!visibility.hides(internalInput))
    }

    @Test
    func namingNothingChangesNothing() {
        let message = ChatEntity(role: .user, text: "Hi")

        #expect(Visibility.default.hides(message, namedAsHidden: []) == Visibility.default.hides(message))
    }
}
