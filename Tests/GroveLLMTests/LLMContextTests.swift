//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveChat
@testable import GroveLLM
import Testing
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif


@Suite("LLM Context to Chat Mapping")
@MainActor
struct LLMContextChatMappingTests {
    /// A 1×1 image, created without touching the file system.
    private static func testImage() -> LLMContextEntity._PlatformImage {
        #if canImport(UIKit)
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        #else
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()
        return image
        #endif
    }

    @Test("Roles map onto their chat counterparts, and system messages stay hidden")
    func rolesMap() {
        var context = LLMContext(systemMessages: ["be nice"])
        context.append(userMessage: "hello")
        context.append(assistantOutputDelta: "hi", isComplete: true)

        let chat = context.chat
        #expect(chat.map(\.role) == [.hidden(type: .system), .user, .assistant(.response)])
        #expect(chat[1].content.text == "hello")
        #expect(chat[2].content.text == "hi")
    }

    @Test("Repeated thinking phases in one interaction collapse into a single chat entity")
    func thinkingPhasesMerge() {
        let interactionId = LLMInteractionId()
        var context = LLMContext()
        context.append(userMessage: "why?")
        context.append(assistantThinkingDelta: "first thought", isComplete: true, interactionId: interactionId)
        context.append(toolCalls: [.init(id: "call_1", name: "lookup", arguments: "{}")], interactionId: interactionId)
        context.append(toolCallResponse: "42", for: "lookup", withId: "call_1", interactionId: interactionId)
        context.append(assistantThinkingDelta: "second thought", isComplete: true, interactionId: interactionId)
        context.append(assistantOutputDelta: "because 42", isComplete: true, interactionId: interactionId)

        let chat = context.chat
        let thinking = chat.filter(\.isThinking)
        #expect(thinking.count == 1, "Both thinking phases of one interaction must fold into one disclosure")
        #expect(thinking.first?.content.text == "first thought\n\nsecond thought")
    }

    @Test("A merged thinking entity is complete only once every phase is")
    func mergedThinkingCompletion() {
        let interactionId = LLMInteractionId()
        var context = LLMContext()
        context.append(assistantThinkingDelta: "done", isComplete: true, interactionId: interactionId)
        context.append(assistantThinkingDelta: "still going", isComplete: false, interactionId: interactionId)

        let thinking = context.chat.first { $0.isThinking }
        #expect(thinking?.complete == false)
    }

    @Test("Thinking phases carry the interaction's start and end dates")
    func thinkingDates() {
        let interactionId = LLMInteractionId()
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 1_012)
        var context = LLMContext()
        context.append(.init(date: start, role: .assistantThinking, interactionId: interactionId, content: "hmm", complete: true))
        context.append(.init(date: end, role: .assistant, interactionId: interactionId, content: "answer", complete: true))

        guard case let .assistant(.thinking(startDate, endDate)) = context.chat[0].role else {
            Issue.record("Expected a thinking entity")
            return
        }
        #expect(startDate == start)
        #expect(endDate == end)
    }

    @Test("A thinking phase's duration spans until its streaming completed")
    func thinkingDurationUsesCompletionDate() throws {
        let interactionId = LLMInteractionId()
        var context = LLMContext()
        context.append(assistantThinkingDelta: "hmm", interactionId: interactionId)
        context.completeAssistantThinkingStreaming(for: interactionId)

        guard case let .assistant(.thinking(startDate, endDate)) = context.chat[0].role else {
            Issue.record("Expected a thinking entity")
            return
        }
        #expect(startDate == context[0].date)
        #expect(endDate == context[0].completionDate)
    }

    @Test("Images sent through the chat land in the context as inline payloads")
    func imageWriteBack() throws {
        var context = LLMContext()
        let entity = ChatEntity(role: .user, content: .images([.image(Self.testImage())], text: "What is this?"))
        var chat = context.chat
        chat.append(entity)
        context.chat = chat

        #expect(context.count == 2)
        #expect(context[0].role == .user)
        #expect(context[0]._imageContent != nil)
        #expect(context[0]._imageContent?.contentType == "image/jpeg")
        #expect(context[1].role == .user)
        #expect(context[1].content == "What is this?")
        #expect(context[1].id == entity.id, "The text entity carries the chat entity's identity")

        // Idempotent: assigning the same chat again must not duplicate anything.
        context.chat = chat
        #expect(context.count == 2)
    }

    @Test("An image-only message carries the chat entity's identity on its final image")
    func imageOnlyWriteBack() {
        var context = LLMContext()
        let entity = ChatEntity(role: .user, content: .images([.image(Self.testImage()), .image(Self.testImage())], text: nil))
        var chat = context.chat
        chat.append(entity)
        context.chat = chat

        #expect(context.count == 2)
        #expect(context.last?.id == entity.id)

        context.chat = chat
        #expect(context.count == 2, "The write-back must stay idempotent without a text entity")
    }

    @Test("Inline image payloads surface in the chat as data URLs")
    func imageProjection() throws {
        var context = LLMContext()
        let contextEntity = try #require(LLMContextEntity(_role: .user, image: Self.testImage(), format: .jpeg(compressionFactor: 0.8)))
        context.append(contextEntity)

        let chatEntity = try #require(context.chat.first)
        let images = chatEntity.content.images
        #expect(!images.isEmpty, "Expected image content, got \(chatEntity.content)")
        #expect(chatEntity.content.text == nil)
        guard case let .url(url) = try #require(images.first) else {
            Issue.record("Expected a data URL")
            return
        }
        #expect(url.scheme == "data")
        // The payload must decode back into an image.
        let data = try Data(contentsOf: url)
        #expect(LLMContextEntity._PlatformImage(data: data) != nil)
    }

    @Test("Writing a new user message back into the chat appends it to the context")
    func userMessageWriteBack() {
        var context = LLMContext()
        context.append(assistantOutputDelta: "hi", isComplete: true)

        var chat = context.chat
        let entity = ChatEntity(role: .user, text: "hello")
        chat.append(entity)
        context.chat = chat

        #expect(context.count == 2)
        #expect(context[1].role == .user)
        #expect(context[1].content == "hello")
        #expect(context[1].id == entity.id)
    }

    @Test("Assistant output written back through the chat is ignored")
    func assistantWriteBackIsIgnored() {
        var context = LLMContext()
        context.append(userMessage: "hello")

        var chat = context.chat
        chat.append(ChatEntity(role: .assistant(.response), text: "should not land in the context"))
        context.chat = chat

        #expect(context.count == 1)
    }

    @Test("Writing back the same chat twice does not duplicate the user message")
    func writeBackIsIdempotent() {
        var context = LLMContext()
        var chat = context.chat
        chat.append(ChatEntity(role: .user, text: "hello"))
        context.chat = chat
        context.chat = chat

        #expect(context.count == 1)
    }

    @Test("Repeated chat projections of the same context are equal")
    func projectionIsStable() throws {
        var context = LLMContext()
        context.append(userMessage: "hello")
        let contextEntity = try #require(LLMContextEntity(_role: .user, image: Self.testImage(), format: .jpeg(compressionFactor: 0.8)))
        context.append(contextEntity)
        context.append(assistantOutputDelta: "hi", isComplete: true)

        // `onChange(of: chat)` in the views relies on this: recomputing the projection must not look like a change.
        let firstProjection = context.chat
        let secondProjection = context.chat
        #expect(firstProjection == secondProjection)
    }
}


@Suite("LLM Context")
struct LLMContextTests {
    @Test("System messages are inserted after the leading ones, or appended to the whole context")
    func systemMessageInsertion() {
        var context = LLMContext(systemMessages: ["first"])
        context.append(userMessage: "hello")
        context.append(systemMessage: "second", to: .leadingSystemMessages)
        context.append(systemMessage: "last", to: .wholeContext)

        #expect(context.map(\.content) == ["first", "second", "hello", "last"])
        #expect(context.map(\.role) == [.system, .system, .user, .system])
    }

    @Test("A mid-conversation system message does not attract new leading prompts")
    func leadingSystemMessagesIgnoreLaterOnes() {
        var context = LLMContext(systemMessages: ["first"])
        context.append(userMessage: "hello")
        context.append(systemMessage: "mid-conversation", to: .wholeContext)
        context.append(systemMessage: "second leading", to: .leadingSystemMessages)

        #expect(context.map(\.content) == ["first", "second leading", "hello", "mid-conversation"])
    }

    @Test("The context round-trips through Codable as a plain entity array")
    func codableRoundTrip() throws {
        var context = LLMContext(systemMessages: ["prompt"])
        context.append(userMessage: "hello")
        context.append(assistantOutputDelta: "hi", isComplete: true)

        let data = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(LLMContext.self, from: data)
        #expect(decoded == context)

        // The wire format stays the plain array the previous `LLMContext` typealias produced.
        let asArray = try JSONDecoder().decode([LLMContextEntity].self, from: data)
        #expect(asArray.count == 3)
    }

    @Test("Clearing keeps only the leading system messages when asked to")
    func clearing() {
        var context = LLMContext(systemMessages: ["prompt"])
        context.append(userMessage: "hello")
        context.append(systemMessage: "mid-conversation", to: .wholeContext)

        var kept = context
        kept.clear(keepLeadingSystemMessages: true)
        #expect(kept.map(\.content) == ["prompt"])

        var cleared = context
        cleared.clear(keepLeadingSystemMessages: false)
        #expect(cleared.isEmpty)
    }

    @Test("Assistant deltas accumulate into one entity until it is marked complete")
    func assistantDeltaAccumulation() {
        let interactionId = LLMInteractionId()
        var context = LLMContext()
        context.append(assistantOutputDelta: "Hello", isComplete: false, interactionId: interactionId)
        context.append(assistantOutputDelta: " world", isComplete: false, interactionId: interactionId)

        #expect(context.count == 1)
        #expect(context[0].content == "Hello world")
        #expect(!context[0].complete)

        context.markAssistantOutputCompleted()
        #expect(context[0].complete)

        // A completed entity is closed: the next delta starts a new one rather than reopening it.
        context.append(assistantOutputDelta: "!", isComplete: false, interactionId: interactionId)
        #expect(context.count == 2)
    }

    @Test("Deltas from a different interaction never merge into the previous one")
    func assistantDeltasAreScopedToTheirInteraction() {
        var context = LLMContext()
        context.append(assistantOutputDelta: "one", isComplete: false, interactionId: LLMInteractionId())
        context.append(assistantOutputDelta: "two", isComplete: false, interactionId: LLMInteractionId())

        #expect(context.count == 2)
        #expect(context.map(\.content) == ["one", "two"])
    }

    @Test("A thinking placeholder is only opened once per streaming part")
    func thinkingPlaceholderIsIdempotent() {
        let interactionId = LLMInteractionId()
        var context = LLMContext()
        context.beginAssistantThinkingPlaceholder(with: interactionId)
        context.beginAssistantThinkingPlaceholder(with: interactionId)
        #expect(context.count == 1)

        context.append(assistantThinkingDelta: "pondering", interactionId: interactionId)
        #expect(context.count == 1)
        #expect(context[0].content == "pondering")

        // A completed part is closed, so the next one opens a fresh entity.
        context.completeAssistantThinkingStreaming(for: interactionId)
        context.beginAssistantThinkingPlaceholder(with: interactionId)
        #expect(context.count == 2)
    }

    @Test("Only an in-progress thinking entity is discarded on cancellation")
    func removingIncompleteThinking() {
        let interactionId = LLMInteractionId()
        var context = LLMContext()
        context.append(assistantThinkingDelta: "half a thought", interactionId: interactionId)
        context.removeIncompleteAssistantThinking(for: interactionId)
        #expect(context.isEmpty)

        context.append(assistantThinkingDelta: "a whole thought", isComplete: true, interactionId: interactionId)
        context.removeIncompleteAssistantThinking(for: interactionId)
        #expect(context.count == 1, "A completed thinking entity must survive")
    }

    @Test("Completing a streamed entity stamps when its streaming ended")
    func completionDates() throws {
        let interactionId = LLMInteractionId()
        var context = LLMContext()
        context.append(assistantThinkingDelta: "pondering", interactionId: interactionId)
        #expect(context[0].completionDate == nil)

        context.completeAssistantThinkingStreaming(for: interactionId)
        let completionDate = try #require(context[0].completionDate)
        #expect(completionDate >= context[0].date)

        // Completing again must not move the stamp.
        context.completeAssistantThinkingStreaming(for: interactionId)
        #expect(context[0].completionDate == completionDate)
    }

    @Test("Completing thinking only touches the matching interaction")
    func completingThinkingIsScopedToItsInteraction() {
        let first = LLMInteractionId()
        let second = LLMInteractionId()
        var context = LLMContext()
        context.append(assistantThinkingDelta: "a", interactionId: first)
        context.append(assistantThinkingDelta: "b", interactionId: second)

        context.completeAssistantThinkingStreaming(for: first)
        #expect(context[0].complete)
        #expect(!context[1].complete)
    }

    @Test("Tool calls and their responses round-trip through the context")
    func toolCalls() {
        let interactionId = LLMInteractionId()
        var context = LLMContext()
        context.append(toolCalls: [.init(id: "call_1", name: "get_weather", arguments: "{}")], interactionId: interactionId)
        context.append(toolCallResponse: "21 °C", for: "get_weather", withId: "call_1", interactionId: interactionId)

        guard case .toolCalls(let calls) = context[0].role else {
            Issue.record("Expected a toolCalls entity")
            return
        }
        #expect(calls.map(\.id) == ["call_1"])
        #expect(context[1].role == .toolCallResponse(id: "call_1", name: "get_weather"))
        #expect(context[1].content == "21 °C")
    }
}


extension ChatEntity {
    fileprivate var isThinking: Bool {
        if case .assistant(.thinking) = role {
            true
        } else {
            false
        }
    }
}
