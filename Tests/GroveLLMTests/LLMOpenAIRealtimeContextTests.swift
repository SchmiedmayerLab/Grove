//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveLLM
@testable import GroveLLMOpenAIRealtime
import Testing


@Suite("Realtime Assistant Context")
struct LLMOpenAIRealtimeContextTests {
    @Test("Interleaved responses and content parts retain their own text")
    func interleavedParts() throws {
        var transcripts = RealtimeAssistantTranscripts()
        var context = LLMContext()
        transcripts.consume(.responseCreated(.init(id: "first", generationId: "generation", status: .inProgress)), context: &context)
        transcripts.consume(delta("later", response: "first", item: "first-item", part: 1), context: &context)
        transcripts.consume(delta("Other", response: "second", item: "second-item"), context: &context)
        context.append(userMessage: "A user spoke again")
        transcripts.consume(delta("First ", response: "first", item: "first-item"), context: &context)
        transcripts.consume(delta(" part", response: "first", item: "first-item", part: 1), context: &context)
        transcripts.consume(delta(" response", response: "second", item: "second-item"), context: &context)

        #expect(context.count == 3)
        #expect(try message("first-item", in: context).content == "First later part")
        #expect(try message("first-item", in: context).interactionId == LLMInteractionId("generation"))
        #expect(try message("second-item", in: context).content == "Other response")
        #expect(context.last?.content == "A user spoke again")
    }

    @Test("Final transcripts replace deltas and remain open until their response finishes")
    func finalTranscripts() throws {
        var transcripts = RealtimeAssistantTranscripts()
        var context = LLMContext()
        transcripts.consume(delta("Wrong words", response: "first", item: "first-item"), context: &context)
        transcripts.consume(done("Correct words", response: "first", item: "first-item"), context: &context)
        transcripts.consume(done("Correct words", response: "first", item: "first-item"), context: &context)
        transcripts.consume(delta(" stale delta", response: "first", item: "first-item"), context: &context)
        transcripts.consume(done(" second part", response: "first", item: "first-item", part: 1), context: &context)
        #expect(context.count == 1)
        let unfinished = try message("first-item", in: context)
        #expect(unfinished.content == "Correct words second part")
        #expect(!unfinished.complete)
        #expect(unfinished.completionDate == nil)

        transcripts.consume(.responseDone(.init(id: "first", status: .completed)), context: &context)
        let finished = try message("first-item", in: context)
        #expect(finished.complete)
        #expect(finished.completionDate != nil)
        #expect(finished.date == unfinished.date)

        transcripts.consume(done("Correct words", response: "first", item: "first-item"), context: &context)
        transcripts.consume(.responseDone(.init(id: "first", status: .completed)), context: &context)
        #expect(context.count == 1)
        #expect(try message("first-item", in: context) == finished)
    }

    @Test("A final transcript without deltas creates one assistant message")
    func doneOnly() throws {
        var transcripts = RealtimeAssistantTranscripts()
        var context = LLMContext()
        transcripts.consume(done("Full transcript", response: "first", item: "first-item"), context: &context)
        transcripts.consume(.responseDone(.init(id: "first", status: .completed)), context: &context)
        #expect(context.count == 1)
        #expect(try message("first-item", in: context).content == "Full transcript")
        #expect(try message("first-item", in: context).complete)
    }

    @Test("A terminal response finalizes only its own partial messages", arguments: [
        LLMRealtimeAudioEvent.Response.Status.completed, .cancelled, .failed, .incomplete
    ])
    func matchingCompletion(status: LLMRealtimeAudioEvent.Response.Status) throws {
        var transcripts = RealtimeAssistantTranscripts()
        var context = LLMContext()
        transcripts.consume(delta("First", response: "first", item: "first-item"), context: &context)
        transcripts.consume(delta("Second item", response: "first", item: "first-other-item"), context: &context)
        transcripts.consume(delta("Other response", response: "second", item: "second-item"), context: &context)
        let unrelated = LLMContextEntity(role: .assistant, content: "Unrelated", complete: false)
        context.append(unrelated)
        transcripts.consume(.responseDone(.init(id: "first", status: status)), context: &context)

        #expect(try message("first-item", in: context).complete)
        #expect(try message("first-item", in: context).content == "First")
        #expect(try message("first-other-item", in: context).complete)
        #expect(!(try message("second-item", in: context).complete))
        #expect(try message("second-item", in: context).completionDate == nil)
        #expect(context.last == unrelated)
    }

    @Test("Updating a known item preserves its identity and date")
    func preservesExistingMessage() throws {
        let id = UUID.deterministic(from: "first-item")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let interaction = LLMInteractionId("existing")
        var context: LLMContext = [.init(id: id, date: date, role: .assistant, interactionId: interaction, content: "", complete: false)]
        var transcripts = RealtimeAssistantTranscripts()
        transcripts.consume(delta("Hello", response: "first", item: "first-item"), context: &context)
        transcripts.consume(done("Hello world", response: "first", item: "first-item"), context: &context)
        transcripts.consume(.responseDone(.init(id: "first", status: .completed)), context: &context)

        let finished = try message("first-item", in: context)
        #expect(context.count == 1)
        #expect(finished.id == id)
        #expect(finished.date == date)
        #expect(finished.interactionId == interaction)
        #expect(finished.content == "Hello world")
        #expect(finished.complete)
        #expect(finished.completionDate != nil)
    }

    @Test("Reset finalizes tracked messages without finalizing unrelated output")
    func reset() throws {
        var transcripts = RealtimeAssistantTranscripts()
        var context = LLMContext()
        transcripts.consume(delta("Partial", response: "first", item: "first-item"), context: &context)
        let unrelated = LLMContextEntity(role: .assistant, content: "Unrelated", complete: false)
        context.append(unrelated)
        transcripts.reset(context: &context)
        let finished = try message("first-item", in: context)
        #expect(finished.complete)
        #expect(finished.completionDate != nil)
        #expect(context.last == unrelated)
        transcripts.consume(delta(" stale", response: "first", item: "first-item"), context: &context)
        #expect(try message("first-item", in: context) == finished)
    }

    private func message(_ itemId: String, in context: LLMContext) throws -> LLMContextEntity {
        try #require(context.first { $0.id == UUID.deterministic(from: itemId) })
    }

    private func delta(_ text: String, response: String, item: String, part: Int = 0) -> LLMRealtimeAudioEvent {
        .assistantTranscriptDelta(.init(responseId: response, itemId: item, contentIndex: part, delta: text))
    }

    private func done(_ text: String, response: String, item: String, part: Int = 0) -> LLMRealtimeAudioEvent {
        .assistantTranscriptDone(.init(responseId: response, itemId: item, contentIndex: part, transcript: text))
    }
}
