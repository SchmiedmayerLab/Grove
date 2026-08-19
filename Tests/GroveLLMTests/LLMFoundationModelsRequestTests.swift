//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import FoundationModels
@testable import GroveLLM
@testable import GroveLLMFoundationModels
import Testing
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif


/// Covers the split of an `LLMContext` into the transcript and prompt `FoundationModels` expects.
///
/// The `@Test` and `@Suite` macros cannot be applied to availability-annotated declarations, so each test opens with
/// a runtime availability check rather than carrying the target's `iOS 27` annotation.
@Suite("LLM FoundationModels Request")
struct LLMFoundationModelsRequestTests {
    /// The concatenated text of a transcript's segments.
    @available(iOS 26, macOS 26, visionOS 26, *)
    private static func text(of segments: [Transcript.Segment]) -> String {
        segments
            .compactMap { segment in
                if case let .text(text) = segment {
                    text.content
                } else {
                    nil
                }
            }
            .joined()
    }

    /// A user entity carrying a 1×1 image, created without touching the file system.
    private static func imageEntity() throws -> LLMContextEntity {
        #if canImport(UIKit)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        #else
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()
        #endif
        return try #require(LLMContextEntity(_role: .user, image: image, format: .png))
    }

    @Test("System messages become instructions, ahead of the conversation")
    func systemMessagesBecomeInstructions() throws {
        guard #available(iOS 27, macOS 27, visionOS 27, *) else {
            return
        }
        var context = LLMContext()
        context.append(systemMessage: "Be brief.", to: .leadingSystemMessages)
        context.append(userMessage: "Hello!")

        let request = FoundationModelsRequest(context: context, systemPrompt: "You are a doctor.", includesImages: false)

        let entry = try #require(request.transcript.first)
        guard case let .instructions(instructions) = entry else {
            Issue.record("Expected the transcript to open with instructions, got \(entry)")
            return
        }
        #expect(Self.text(of: instructions.segments) == "You are a doctor.\n\nBe brief.")
        // The instructions are the whole transcript: the single user message is the prompt, not history.
        #expect(request.transcript.count == 1)
    }

    @Test("The trailing user message becomes the prompt, everything before it history")
    func trailingUserMessageBecomesThePrompt() throws {
        guard #available(iOS 27, macOS 27, visionOS 27, *) else {
            return
        }
        var context = LLMContext()
        context.append(userMessage: "First question")
        context.append(assistantOutputDelta: "First answer", isComplete: true)
        context.append(userMessage: "Second question")

        let request = FoundationModelsRequest(context: context, systemPrompt: nil, includesImages: false)

        #expect(request.transcript.count == 2)
        guard case let .prompt(prompt) = request.transcript[0], case let .response(response) = request.transcript[1] else {
            Issue.record("Expected a prompt followed by a response, got \(Array(request.transcript))")
            return
        }
        #expect(Self.text(of: prompt.segments) == "First question")
        #expect(Self.text(of: response.segments) == "First answer")
    }

    @Test("A conversation ending on the assistant keeps every turn as history")
    func conversationEndingOnTheAssistant() throws {
        guard #available(iOS 27, macOS 27, visionOS 27, *) else {
            return
        }
        var context = LLMContext()
        context.append(userMessage: "Question")
        context.append(assistantOutputDelta: "Answer", isComplete: true)

        let request = FoundationModelsRequest(context: context, systemPrompt: nil, includesImages: false)

        #expect(request.transcript.count == 2)
    }

    @Test("Tool calls and their responses are left out of the transcript")
    func toolInteractionsAreLeftOut() throws {
        guard #available(iOS 27, macOS 27, visionOS 27, *) else {
            return
        }
        var context = LLMContext()
        context.append(userMessage: "Question")
        context.append(toolCalls: [.init(id: "1", name: "some_tool", arguments: "{}")])
        context.append(toolCallResponse: "{}", for: "some_tool", withId: "1")

        let request = FoundationModelsRequest(context: context, systemPrompt: nil, includesImages: false)

        // Only the user message remains, and it is the prompt rather than history.
        #expect(request.transcript.isEmpty)
    }

    @Test("An image and its caption are one turn, not two")
    func imageAndCaptionFormOneTurn() throws {
        guard #available(iOS 27, macOS 27, visionOS 27, *) else {
            return
        }
        var context = LLMContext()
        context.append(try Self.imageEntity())
        context.append(userMessage: "What is this?")

        let request = FoundationModelsRequest(context: context, systemPrompt: nil, includesImages: true)

        // Both entities belong to the turn being answered, so nothing is left behind as history.
        #expect(request.transcript.isEmpty)
    }

    @Test("An image reaches the history only when the model can see it")
    func imagesRideAlongOnlyWhenSupported() throws {
        guard #available(iOS 27, macOS 27, visionOS 27, *) else {
            return
        }
        var context = LLMContext()
        context.append(try Self.imageEntity())
        context.append(userMessage: "What is this?")
        context.append(assistantOutputDelta: "A red dot.", isComplete: true)
        context.append(userMessage: "And now?")

        let withImages = FoundationModelsRequest(context: context, systemPrompt: nil, includesImages: true)
        guard case let .prompt(prompt) = try #require(withImages.transcript.first) else {
            Issue.record("Expected the history to open with a prompt")
            return
        }
        #if compiler(>=6.4)
        #expect(prompt.segments.contains(where: { if case .attachment = $0 { true } else { false } }))
        #endif
        #expect(Self.text(of: prompt.segments) == "What is this?")

        let withoutImages = FoundationModelsRequest(context: context, systemPrompt: nil, includesImages: false)
        guard case let .prompt(stripped) = try #require(withoutImages.transcript.first) else {
            Issue.record("Expected the history to open with a prompt")
            return
        }
        #if compiler(>=6.4)
        #expect(!stripped.segments.contains(where: { if case .attachment = $0 { true } else { false } }))
        #endif
        #expect(Self.text(of: stripped.segments) == "What is this?")
    }
}
