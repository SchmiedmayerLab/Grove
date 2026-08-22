//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import GroveLLMOpenAI
import Testing


@Suite("Sampling Controls")
struct LLMOpenAISamplingControlsTests {
    @Test("OpenAI answers for its reasoning models")
    func openAIModels() {
        #expect(!OpenAIPlatformDefinition.ModelType.gpt5_5.supportsSamplingControls)
        #expect(!OpenAIPlatformDefinition.ModelType.o3.supportsSamplingControls)
        #expect(OpenAIPlatformDefinition.ModelType.gpt4o.supportsSamplingControls)
        // The chat variant of the family does not reason, and keeps the controls.
        #expect(OpenAIPlatformDefinition.ModelType.gpt5_chat.supportsSamplingControls)
    }

    @Test("A model that takes them is left alone")
    func keepsAcceptedControls() {
        let parameters = LLMOpenAIModelParameters(temperature: 0, topP: 0.5, presencePenalty: 1)
        let accepted = parameters.accepted(by: OpenAIPlatformDefinition.ModelType.gpt4o)

        #expect(accepted.temperature == 0)
        #expect(accepted.topP == 0.5)
        #expect(accepted.presencePenalty == 1)
    }

    @Test("Parameters a model takes anyway survive a model that refuses sampling")
    func keepsUnrelatedParameters() {
        let parameters = LLMOpenAIModelParameters(stopSequence: ["stop"], maxOutputLength: 512)
        let accepted = parameters.accepted(by: OpenAIPlatformDefinition.ModelType.gpt5_5)

        #expect(accepted.maxOutputLength == 512)
        #expect(accepted.stopSequence == ["stop"])
        #expect(accepted.temperature == nil)
    }
}
