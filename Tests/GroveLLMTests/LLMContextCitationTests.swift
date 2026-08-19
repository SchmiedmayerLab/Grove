//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveLLM
import Testing


/// Covers where a model's sources end up once it has answered.
///
/// Sources are merged onto the answer rather than appended beside it, so this only works if the answer is already
/// in the context and is the one being looked for. Both of those have been wrong: a session that leaves the
/// consumer to append its own output produces no interaction id to match on, which is the *default* configuration
/// and the one ``LLMChatView`` drives — so every test that pinned `injectIntoContext: true` stayed green while
/// sources silently vanished in the shipping path.
@Suite("LLM Context Citations")
struct LLMContextCitationTests {
    private static let sources: [LLMCitation] = [
        .init(title: "Reykjavík", source: .web(URL(string: "https://en.wikipedia.org/wiki/Reykjav%C3%ADk")!)),
        .init(title: "Iceland", source: .file(name: "atlas.pdf"))
    ]

    @Test("Sources land on an answer the consumer appended itself, without an interaction id")
    func citationsMergeOntoAConsumerAppendedAnswer() {
        // Exactly what LLMChatView does when the session does not inject its own output.
        var context = LLMContext()
        context.append(userMessage: "What is the capital of Iceland?")
        context.append(assistantOutputDelta: "Reykjavík.", isComplete: false)
        context.markAssistantOutputCompleted()

        // The session knows its interaction; the entity in the context carries none.
        context.append(citations: Self.sources, interactionId: LLMInteractionId())

        #expect(context.last?.citations?.count == 2, "sources have to reach the answer in the default mode")
    }

    @Test("Sources prefer the answer from their own interaction")
    func citationsPreferTheirOwnInteraction() {
        let interaction = LLMInteractionId()
        var context = LLMContext()
        context.append(assistantOutputDelta: "An earlier answer.", isComplete: true)
        context.markAssistantOutputCompleted()
        context.append(assistantOutputDelta: "This turn's answer.", isComplete: true, interactionId: interaction)
        context.markAssistantOutputCompleted()

        context.append(citations: Self.sources, interactionId: interaction)

        #expect(context.last?.citations?.count == 2)
        #expect(context.first?.citations == nil, "an earlier answer must not collect this turn's sources")
    }

    @Test("Sources with nowhere to go are dropped rather than inventing a message")
    func citationsWithoutAnAnswerAreDropped() {
        var context = LLMContext()
        context.append(userMessage: "What is the capital of Iceland?")

        context.append(citations: Self.sources, interactionId: LLMInteractionId())

        #expect(context.count == 1, "no assistant message means nothing to attach to")
        #expect(context.allSatisfy { $0.citations == nil })
    }

    @Test("The same source cited twice collapses, keeping the order it was first seen in")
    func repeatedSourcesCollapse() {
        var context = LLMContext()
        context.append(assistantOutputDelta: "Reykjavík.", isComplete: true)
        context.markAssistantOutputCompleted()

        context.append(citations: Self.sources)
        context.append(citations: Self.sources.reversed())

        #expect(context.last?.citations?.count == 2)
        #expect(context.last?.citations?.first?.title == "Reykjavík")
    }
}
