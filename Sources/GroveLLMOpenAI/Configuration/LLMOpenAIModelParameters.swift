//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GeneratedOpenAIClient
import OpenAPIRuntime

/// Represents the model-specific parameters of OpenAIs LLMs.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct LLMOpenAIModelParameters: Sendable {
    /// The response format of the LLM.
    public enum ResponseFormat {
        case text
        case jsonObject


        var openAiRepresentation: Components.Schemas.CreateChatCompletionRequest.Value2Payload.response_formatPayload {
            switch self {
            case .text:
                .ResponseFormatText(.init(_type: .text))
            case .jsonObject:
                .ResponseFormatJsonObject(.init(_type: .json_object))
            }
        }

        /// The same choice as the Responses API spells it, where the format sits under `text`.
        var responsesRepresentation: Components.Schemas.TextResponseFormatConfiguration {
            switch self {
            case .text:
                .ResponseFormatText(.init(_type: .text))
            case .jsonObject:
                .ResponseFormatJsonObject(.init(_type: .json_object))
            }
        }
    }


    /// The format for model responses.
    let responseFormat: Components.Schemas.CreateChatCompletionRequest.Value2Payload.response_formatPayload?
    /// The same format, as the Responses API takes it.
    ///
    /// The two APIs spell the choice differently, so both are kept: whichever path a model takes, it asks for the
    /// format the caller set rather than quietly answering in prose.
    let responsesTextFormat: Components.Schemas.TextResponseFormatConfiguration?
    /// The sampling temperature (0 to 2). Higher values increase randomness, lower values enhance focus.
    var temperature: Double?
    /// Nucleus sampling threshold. Considers tokens with top_p probability mass. Alternative to temperature sampling.
    var topP: Double?
    /// The number of generated chat completions per input.
    let completionsPerOutput: Int?
    /// Sequences (up to 4) where generation stops. Output doesn't include these sequences.
    let stopSequence: [String]
    /// Maximum token count for each completion.
    let maxOutputLength: Int?
    /// Adjusts new topic exploration (-2.0 to 2.0). Higher values encourage novelty.
    var presencePenalty: Double?
    /// Controls repetition (-2.0 to 2.0). Higher values reduce the likelihood of repeating content.
    var frequencyPenalty: Double?
    /// Alters specific token's likelihood in completion.
    var logitBias: Components.Schemas.CreateChatCompletionRequest.Value2Payload.logit_biasPayload
    
    
    /// Initializes ``LLMOpenAIModelParameters`` for OpenAI model configuration.
    ///
    /// - Parameters:
    ///   - responseFormat: Format for model responses.
    ///   - temperature: Sampling temperature (0 to 2); higher values (e.g., 0.8) increase randomness, lower values (e.g., 0.2) enhance focus. Adjust this or topP, not both.
    ///   - topP: Nucleus sampling threshold; considers tokens with top_p probability mass. Alternative to temperature sampling.
    ///   - completionsPerOutput: Number of generated chat completions (choices) per input, defaults to 1 choice.
    ///   - stopSequence: Sequences (up to 4) where generation stops; output doesn't include these sequences.
    ///   - maxOutputLength: Maximum token count for each completion.
    ///   - presencePenalty: Adjusts new topic exploration (-2.0 to 2.0); higher values encourage novelty.
    ///   - frequencyPenalty: Controls repetition (-2.0 to 2.0); higher values reduce likelihood of repeating content.
    ///   - logitBias: Alters specific token's likelihood in completion.
    public init(
        responseFormat: ResponseFormat? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        completionsPerOutput: Int? = nil,
        stopSequence: [String] = [],
        maxOutputLength: Int? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        logitBias: [String: Int] = [:]
    ) {
        self.responseFormat = responseFormat?.openAiRepresentation
        self.responsesTextFormat = responseFormat?.responsesRepresentation
        self.temperature = temperature
        self.topP = topP
        self.completionsPerOutput = completionsPerOutput
        self.stopSequence = stopSequence
        self.maxOutputLength = maxOutputLength
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.logitBias = Components.Schemas.CreateChatCompletionRequest.Value2Payload.logit_biasPayload(additionalProperties: logitBias)
    }
}
