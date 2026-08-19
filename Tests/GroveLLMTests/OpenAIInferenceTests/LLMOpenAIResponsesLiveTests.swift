//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import Grove
@testable import GroveLLM
@testable import GroveLLMOpenAI
import GroveTesting
import Testing
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif


/// A tool with an unmistakable return value, so a model either called it or it didn't.
private struct ResponsesLiveTestFunction: LLMTool {
    let name = "perform_test"
    let description = "Performs a test and returns the value that proves the function was called"

    func execute() async throws -> String? {
        "The value to return to ensure the test was succesful is \"abcdefghijklmnopqrstuvwxyz\""
    }
}


/// Exercises the Responses API against OpenAI itself.
///
/// Everything else covering this path is mocked, which pins the shapes this code builds but not whether OpenAI
/// accepts them. These tests are the ones that would have caught a request the API rejects.
///
/// Pass `OPENAI_API_TOKEN` on the `xcodebuild` command line to run them; without it the suite is skipped.
@Suite(
    "LLM OpenAI Responses API (Live)",
    .disabled(
        if: ProcessInfo.processInfo.environment["OPENAI_API_TOKEN"]?.isEmpty ?? true,
        "Set OPENAI_API_TOKEN to run the live Responses API tests"
    )
)
final class LLMOpenAIResponsesLiveTests {
    /// A reasoning model, so reasoning summaries are in play, and a cheap one for the plain paths.
    static let reasoningModel: OpenAIPlatformDefinition.ModelType = .gpt5_mini
    static let plainModel: OpenAIPlatformDefinition.ModelType = .gpt4_1_mini

    private var platformTask: Task<Void, Never>?

    /// A solid red 256×256 image — small images are not reliably legible to the model, created without touching the file system.
    private static func redSquareEntity() throws -> LLMContextEntity {
        #if canImport(UIKit)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        }
        #else
        let image = NSImage(size: NSSize(width: 256, height: 256))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 256, height: 256).fill()
        image.unlockFocus()
        #endif
        return try #require(LLMContextEntity(_role: .user, image: image, format: .png))
    }

    @MainActor
    @Test("Text streams back and lands in the context as one completed entity")
    func streamsText() async throws {
        let session = try makeSession(modelType: Self.plainModel)
        session.context.append(userMessage: "Reply with exactly the word: ok")

        var output = ""
        for try await piece in try await session.generate() {
            output.append(piece)
        }

        #expect(output.lowercased().contains("ok"))
        #expect(session.state == .ready)
        let assistant = session.context.filter { $0.role == .assistant }
        #expect(assistant.count == 1)
        #expect(assistant.first?.complete == true)
    }

    /// The Responses API keeps the conversation server-side, so the second turn sends only the new message.
    @MainActor
    @Test("A second turn continues the server-side conversation via previous_response_id")
    func continuesServerSideConversation() async throws {
        let session = try makeSession(modelType: Self.plainModel)
        session.context.append(userMessage: "My favourite number is 7. Reply with just: noted")
        for try await _ in try await session.generate() { }

        let firstResponseId = session.lastResponseId
        #expect(firstResponseId != nil, "the first turn should record a response id to continue from")

        session.context.append(userMessage: "What is my favourite number? Reply with the digit only.")
        var second = ""
        for try await piece in try await session.generate() {
            second.append(piece)
        }

        #expect(second.contains("7"), "the server-side conversation lost the first turn: \(second)")
        #expect(session.lastResponseId != firstResponseId, "the second turn should advance the response id")
    }

    @MainActor
    @Test("A reasoning model streams a summary into a thinking entity")
    func reasoningSummariesArrive() async throws {
        let session = try makeSession(modelType: Self.reasoningModel)
        session.context.append(
            userMessage: "A farmer has 17 sheep, and all but 9 run away. How many are left? Answer with the number."
        )

        for try await _ in try await session.generate() { }

        let thinking = session.context.filter { $0.role == .assistantThinking }
        // Whether a summary is emitted at all is OpenAI's call and varies run to run, so an empty one is not a
        // failure of this code — failing on it would make the suite flaky rather than catch anything.
        withKnownIssue("The model may answer without emitting a reasoning summary", isIntermittent: true) {
            try #require(!thinking.isEmpty)
        }
        guard !thinking.isEmpty else {
            return
        }
        #expect(!thinking.contains { !$0.complete })
        #expect(thinking.contains { !$0.content.isEmpty })
        // Thinking and the answer belong to the same interaction, which is what groups them in the UI.
        let answer = try #require(session.context.last { $0.role == .assistant })
        #expect(thinking.first?.interactionId == answer.interactionId)
    }

    @MainActor
    @Test("A tool is called and its output is fed back over the Responses API")
    func functionCallingRoundTrips() async throws {
        let session = try makeSession(modelType: Self.plainModel) {
            ResponsesLiveTestFunction()
        }
        session.context.append(userMessage: "Call the perform_test function and tell me the value it returns.")

        var output = ""
        for try await piece in try await session.generate() {
            output.append(piece)
        }

        #expect(output.contains("abcdefghijklmnopqrstuvwxyz"), "the tool was not used: \(output)")
        // The call and its output are both recorded, so the transcript explains itself.
        #expect(session.context.contains { if case .toolCalls = $0.role { true } else { false } })
        #expect(session.context.contains { if case .toolCallResponse = $0.role { true } else { false } })
    }

    @MainActor
    @Test("An image is accepted alongside the text of a message")
    func acceptsImages() async throws {
        let session = try makeSession(modelType: Self.plainModel)
        session.context.append(try Self.redSquareEntity())
        session.context.append(userMessage: "What colour is this image? Answer with one word.")

        var output = ""
        for try await piece in try await session.generate() {
            output.append(piece)
        }

        #expect(output.lowercased().contains("red"), "the image did not reach the model: \(output)")
    }

    /// An empty context has nothing to answer, and should say so rather than surfacing OpenAI's cryptic rejection.
    @MainActor
    @Test("Generating with an empty context fails before the request is sent")
    func emptyContextFailsFast() async throws {
        let session = try makeSession(modelType: Self.plainModel)

        do {
            let stream = try await session.generate()
            for try await _ in stream { }
            Issue.record("An empty context should not have produced a request")
        } catch let error as LLMOpenAIError {
            #expect(error == .invalidRequest)
        } catch {
            Issue.record("Unexpected error for an empty context: \(error)")
        }
    }


    @MainActor
    private func makeSession(
        modelType: OpenAIPlatformDefinition.ModelType,
        @LLMToolBuilder _ functions: () -> _LLMToolCollection = { _LLMToolCollection() }
    ) throws -> LLMOpenAISession {
        let token = try #require(ProcessInfo.processInfo.environment["OPENAI_API_TOKEN"])
        let platform = LLMOpenAIPlatform(configuration: .init(authToken: .constant(token)))
        let runner = LLMRunner { platform }
        withDependencyResolution { runner }
        platformTask = Task { await platform.run() }

        #expect(
            LLMOpenAIAPIModePolicy.perModel.resolve(for: modelType) == .responses,
            "\(modelType.rawValue) must route through the Responses API for this suite to mean anything"
        )
        return platform(
            with: LLMOpenAISchema(parameters: .init(modelType: modelType), injectIntoContext: true, functions)
        )
    }


    deinit {
        platformTask?.cancel()
    }
}
