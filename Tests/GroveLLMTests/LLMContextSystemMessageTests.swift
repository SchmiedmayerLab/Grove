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


@Suite("LLM Context System Messages")
struct LLMContextSystemMessageTests {
    private let instructionID = UUID()

    @Test("An identified system message is recorded once")
    func recordsUnderIdentifier() {
        var context = LLMContext()
        context.append(userMessage: "Hello")

        context.set(systemMessage: "Answer briefly.", id: instructionID)

        let recorded = context.filter { $0.id == instructionID }
        #expect(recorded.count == 1)
        #expect(recorded.first?.role == .system)
        #expect(recorded.first?.content == "Answer briefly.")
    }

    @Test("Setting it again rewrites the entity instead of adding another")
    func rewritesInPlace() {
        var context = LLMContext()
        context.set(systemMessage: "Answer briefly.", id: instructionID)
        context.append(userMessage: "Hello")
        let countBefore = context.count

        context.set(systemMessage: "Answer in detail.", id: instructionID)

        // The count is what a transport holding server-side state checks to see whether the conversation it
        // already submitted still holds; a rewrite must leave it alone.
        #expect(context.count == countBefore)
        #expect(context.filter { $0.role == .system }.map(\.content) == ["Answer in detail."])
    }

    @Test("A first recording honours the requested position")
    func placesFirstRecording() {
        var context = LLMContext()
        context.append(systemMessage: "The instructions.", to: .leadingSystemMessages)
        context.append(userMessage: "Hello")

        context.set(systemMessage: "Answer briefly.", id: instructionID, to: .leadingSystemMessages)

        #expect(context.prefix(2).allSatisfy { $0.role == .system })
        #expect(context.last?.role == .user)
    }

    @Test("Appending a system message keeps the identifier it was given")
    func appendKeepsIdentifier() {
        var context = LLMContext()

        context.append(systemMessage: "The instructions.", to: .wholeContext, id: instructionID)

        #expect(context.first?.id == instructionID)
    }
}
