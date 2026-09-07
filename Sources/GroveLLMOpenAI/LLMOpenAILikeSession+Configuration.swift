//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GeneratedOpenAIClient
import GroveLLM
import OpenAPIRuntime


/// The incompatibility that would make a Chat Completions request silently lose user input, if any.
@available(iOS 18, macOS 15, watchOS 11, *)
func chatCompletionsCompatibilityError(in context: LLMContext) -> LLMOpenAIError? {
    context.contains { $0._fileContent != nil } ? .fileAttachmentsRequireResponsesAPI : nil
}


/// Stops an incompatible request before the legacy API can discard its attachment.
@available(iOS 18, macOS 15, watchOS 11, *)
private func validateChatCompletionsCompatibility(of context: LLMContext) throws {
    guard let compatibilityError = chatCompletionsCompatibilityError(in: context) else {
        return
    }
    #if DEBUG
    assertionFailure(
        """
        GroveLLMOpenAI: File attachments are not supported by the Chat Completions API. Configure the model to use \
        the Responses API, and only fall back to Chat Completions when Responses is unavailable.
        """
    )
    #endif
    throw compatibilityError
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMOpenAILikeSession {
    /// Warns when a search was asked for on the one path that cannot serve it.
    ///
    /// Only the Responses API offers the hosted search tool. Saying so is the difference between a model that chose
    /// not to search and a model that was never given the option — which look identical in the answer.
    private func warnAboutUnsupportedWebSearch() {
        if schema.searchesTheWeb {
            Self.logger.warning(
                """
                GroveLLMOpenAI: `searchesTheWeb` is set, but this model is being called through the Chat Completions \
                API, which does not offer the hosted web search tool. The model will answer without searching and \
                will cite nothing. Use a model that takes the Responses API, or set `apiMode` to `.fixed(.responses)`.
                """
            )
        }
        if schema.generatesImages {
            Self.logger.warning(
                """
                GroveLLMOpenAI: `generatesImages` is set, but this model is being called through the Chat Completions \
                API, which does not offer the hosted image generation tool. The model will answer with text only.
                """
            )
        }
    }

    /// Builds an `Operations.createChatCompletion.Input` for the Chat Completions API.
    func openAIChatQuery() async throws -> Operations.createChatCompletion.Input {
        let context = await context
        try validateChatCompletionsCompatibility(of: context)
        warnAboutUnsupportedWebSearch()
        let functions: [Components.Schemas.CreateChatCompletionRequest.Value2Payload.toolsPayloadPayload] =
            try schema.functions.values.compactMap { function in
                .ChatCompletionTool(
                    Components.Schemas.ChatCompletionTool(
                        _type: .function,
                        function: Components.Schemas.FunctionObject(
                            description: function.description,
                            name: function.name,
                            parameters: try function.schema
                        )
                    )
                )
            }
        let modelParameters = schema.modelParameters.accepted(by: schema.parameters.modelType)
        let stop: Components.Schemas.StopConfiguration? = modelParameters.stopSequence.isEmpty
            ? nil
            : .case2(modelParameters.stopSequence)
        return Operations.createChatCompletion.Input(
            body: .json(
                Components.Schemas.CreateChatCompletionRequest(
                    value1: .init(
                        value1: .init(
                            temperature: modelParameters.temperature,
                            top_p: modelParameters.topP
                        ),
                        value2: .init()
                    ),
                    value2: .init(
                        messages: context.compactMap { $0.toChatMessage() },
                        model: .init(value1: schema.parameters.modelType.rawValue),
                        max_completion_tokens: modelParameters.maxOutputLength,
                        frequency_penalty: modelParameters.frequencyPenalty,
                        presence_penalty: modelParameters.presencePenalty,
                        response_format: modelParameters.responseFormat,
                        stream: true,
                        stop: stop,
                        logit_bias: modelParameters.logitBias.additionalProperties.isEmpty
                            ? nil
                            : modelParameters.logitBias,
                        n: modelParameters.completionsPerOutput,
                        tools: functions.isEmpty ? nil : functions,
                        tool_choice: nil
                    )
                )
            )
        )
    }
}
