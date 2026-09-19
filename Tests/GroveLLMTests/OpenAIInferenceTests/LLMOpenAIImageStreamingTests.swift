//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import GroveLLM
@testable import GroveLLMOpenAI
import Testing


@Suite("Generated image stream cleanup")
struct LLMOpenAIImageStreamingTests {
    @MainActor
    @Test("Terminal responses discard unfinished images and preserve delivered images", arguments: ["completed", "incomplete", "eof"])
    func removesUnfinishedImages(ending: String) async throws {
        let platform = LLMOpenAIPlatform(configuration: .init(authToken: .constant("mocked-token")))
        let session = LLMOpenAISession(
            platform,
            schema: .init(parameters: .init(modelType: .gpt5_mini), injectIntoContext: true),
            keychainStorage: nil
        )
        let platformTask = Task { await platform.run() }
        defer { platformTask.cancel() }
        session.context.append(userMessage: "Draw two trees")
        let unrelatedInteraction = LLMInteractionId()
        session.context.append(assistantImage: .generating, interactionId: unrelatedInteraction)

        let client = LLMOpenAIInferenceTests.MockChatClient()
        client.createResponseHandler = { _ in
            var builder = ResponsesStreamBuilder()
            builder.created()
            builder.imageAdded()
            builder.imageDone(succeeded: true)
            builder.imageAdded()
            builder.imageDone(succeeded: false)
            if ending == "completed" {
                builder.completed()
            } else if ending == "incomplete" {
                builder.incomplete()
            }
            return builder.output()
        }
        session.openAiClient = client

        for try await _ in try await session.generate() { }

        let images = session.context.filter { $0._imageContent != nil }
        #expect(images.count == 2)
        #expect(images.first?.interactionId == unrelatedInteraction)
        #expect(images.last?._imageContent?.base64Image == "aGVsbG8=")
        #expect(session.state == .ready)
    }
}
