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


@Suite("Image Generation")
struct LLMOpenAIImageGenerationTests {
    @Test("The mainline OpenAI models draw, the reasoning-only and legacy ones do not")
    func openAIModelsThatDraw() {
        #expect(OpenAIPlatformDefinition.ModelType.gpt5_4.supportsImageGeneration)
        #expect(OpenAIPlatformDefinition.ModelType.gpt4_1_mini.supportsImageGeneration)
        #expect(OpenAIPlatformDefinition.ModelType.o3.supportsImageGeneration)
        #expect(!OpenAIPlatformDefinition.ModelType.gpt5_chat.supportsImageGeneration)
        #expect(!OpenAIPlatformDefinition.ModelType.o4_mini.supportsImageGeneration)
        #expect(!OpenAIPlatformDefinition.ModelType.gpt3_5_turbo.supportsImageGeneration)
    }

    @Test("A finished image_generation_call yields the picture in its output format")
    func finishedImageItemIsParsed() throws {
        let item: [String: Any] = [
            "type": "image_generation_call", "status": "completed", "output_format": "jpeg", "result": "aGVsbG8="
        ]
        let image = try #require(LLMOpenAISession.generatedImage(fromOutputItem: item))
        #expect(image.contentType == "image/jpeg")
        #expect(image.base64Image == "aGVsbG8=")
    }

    @Test("The format defaults to PNG")
    func formatDefaultsToPNG() throws {
        let item: [String: Any] = ["type": "image_generation_call", "result": "aGVsbG8="]
        #expect(try #require(LLMOpenAISession.generatedImage(fromOutputItem: item)).contentType == "image/png")
    }

    @Test("Unfinished, empty, and unrelated items are ignored")
    func otherItemsAreIgnored() {
        #expect(LLMOpenAISession.generatedImage(fromOutputItem: ["type": "image_generation_call", "status": "in_progress"]) == nil)
        #expect(LLMOpenAISession.generatedImage(fromOutputItem: ["type": "image_generation_call", "result": ""]) == nil)
        #expect(LLMOpenAISession.generatedImage(fromOutputItem: ["type": "message", "result": "aGVsbG8="]) == nil)
    }

    @Test("A generated image lands in the context as a complete assistant message")
    func generatedImageJoinsTheContext() {
        var context = LLMContext()
        context.append(assistantImage: .init(contentType: "image/png", base64Image: "aGVsbG8="))
        let entity = context.last
        #expect(entity?.role == .assistant)
        #expect(entity?.complete == true)
        #expect(entity?._imageContent?.base64Image == "aGVsbG8=")
        #expect(entity?.toResponsesInputItems().isEmpty == true)
    }
}
