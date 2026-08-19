//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GeneratedOpenAIClient
import GroveLLM
import OpenAPIRuntime


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMOpenAILikeSession {
    /// Whether a Responses API request that failed with this error is worth retrying without streaming.
    ///
    /// Only failures that plausibly come from the streaming transport itself qualify. An unusable token or an
    /// exhausted quota fails the same way unstreamed, so retrying those would cost a second request and report
    /// the same error twice over.
    static func isWorthRetryingWithoutStreaming(_ error: any LLMError) -> Bool {
        guard let error = error as? LLMOpenAIError else {
            return false
        }
        return switch error {
        case .generationError, .connectivityIssues:
            true
        case .invalidRequest, .missingAPITokenInKeychain, .invalidAPIToken, .storageError, .insufficientQuota,
             .fileAttachmentsRequireResponsesAPI, .modelAccessError, .invalidToolCallName, .invalidToolCallArguments,
             .toolCallError, .toolCallSchemaExtractionError:
            false
        }
    }

    /// Runs one Responses API request without streaming, surfacing its output as if it had streamed.
    ///
    /// A gateway can implement `/v1/responses` yet fail to stream it — Stanford's LiteLLM proxy answers a
    /// `stream: true` request with a 500 and serves the same request unstreamed at 200. Falling back keeps the
    /// per-model policy usable there: the answer arrives in one piece rather than not at all.
    ///
    /// - Returns: The function calls the model requested, if any.
    func fetchResponseWithoutStreaming(
        with continuationObserver: ContinuationObserver<String, any Error>,
        interactionId: LLMInteractionId
    ) async throws -> [LLMOpenAIStreamResult.FunctionCall] {
        let response: Operations.createResponse.Output
        do {
            response = try await openAiClient.createResponse(openAIResponsesQuery(stream: false))
        } catch let error as ClientError {
            Self.logger.error("GroveLLMOpenAI: Connectivity Issues with the OpenAI API: \(error)")
            throw ResponsesGenerationError(llmError: LLMOpenAIError.connectivityIssues(error))
        } catch let error as LLMOpenAIError {
            throw ResponsesGenerationError(llmError: error)
        }

        if case let .undocumented(statusCode: statusCode, _) = response {
            throw ResponsesGenerationError(llmError: handleErrorCode(statusCode))
        }
        let payload = try response.ok.body.json

        guard !continuationObserver.isCancelled else {
            Self.logger.warning("GroveLLMOpenAI: Generation cancelled by the user.")
            await cleanUpInterruptedStreaming(interactionId: interactionId)
            return []
        }

        // A failed generation arrives as a 200 with `status: "failed"`, so the status decides whether this counts
        // as an answer at all. Committing first would mark the input as delivered and chain the next turn onto a
        // response the server never produced.
        if payload.value3.status == .failed {
            let message = payload.value3.error?.message ?? "Unknown error"
            Self.logger.error("GroveLLMOpenAI: Response failed: \(message)")
            throw ResponsesGenerationError(llmError: LLMOpenAIError.generationError)
        }

        // The server now holds everything this request carried; only re-send what comes after it.
        responsesConversation.withLock { state in
            state.commitPendingContext(responseId: payload.value3.id)
        }

        return await surface(payload.value3.output, with: continuationObserver, interactionId: interactionId)
    }

    /// Pushes a complete response's output into the context and the continuation, in the order a stream would have.
    private func surface(
        _ output: [Components.Schemas.OutputItem],
        with continuationObserver: ContinuationObserver<String, any Error>,
        interactionId: LLMInteractionId
    ) async -> [LLMOpenAIStreamResult.FunctionCall] {
        var functionCalls: [LLMOpenAIStreamResult.FunctionCall] = []

        for item in output {
            switch item {
            case .reasoning(let reasoning):
                let summary = reasoning.summary.map(\.text).joined(separator: "\n\n")
                guard !summary.isEmpty else {
                    continue
                }
                await MainActor.run {
                    context.beginAssistantThinkingPlaceholder(with: interactionId)
                    context.append(assistantThinkingDelta: summary, interactionId: interactionId)
                    context.completeAssistantThinkingStreaming(for: interactionId)
                }
            case .message(let message):
                await surface(message, with: continuationObserver, interactionId: interactionId)
            case .function_call(let call):
                functionCalls.append(.init(name: call.name, id: call.call_id, arguments: call.arguments))
            default:
                // A server-run tool whose result is already reflected in the message items above. Logged rather
                // than dropped silently, so an item type worth supporting shows up instead of going missing.
                Self.logger.debug("GroveLLMOpenAI: Unhandled response output item: \(String(describing: item))")
            }
        }

        // Nothing above may have closed a placeholder — a response carrying only a function call never does.
        await MainActor.run {
            context.completeAssistantThinkingStreaming(for: interactionId)
        }
        return functionCalls
    }

    /// Puts one assistant message — its text and the sources behind it — into the context.
    private func surface(
        _ message: Components.Schemas.OutputMessage,
        with continuationObserver: ContinuationObserver<String, any Error>,
        interactionId: LLMInteractionId
    ) async {
                // A refusal is the model's user-facing answer; it surfaces exactly like output text.
                let text = message.content
                    .map { content in
                        switch content {
                        case .output_text(let output): output.text
                        case .refusal(let refusal): refusal.refusal
                        }
                    }
                    .joined()
                let annotations: [Components.Schemas.Annotation] = message.content.flatMap { content in
                    guard case .output_text(let output) = content else {
                        return [Components.Schemas.Annotation]()
                    }
                    return output.annotations
                }
                let citations = Self.citations(from: annotations)
                guard !text.isEmpty else {
                    return
                }
                await MainActor.run {
                    context.completeAssistantThinkingStreaming(for: interactionId)
                    if schema.injectIntoContext {
                        context.append(assistantOutputDelta: text, isComplete: true, interactionId: interactionId)
                    }
                }
                continuationObserver.continuation.yield(text)
                // Sources are merged onto the answer, so they can only be written once the answer is in the context.
                if !citations.isEmpty {
                    await MainActor.run {
                        context.append(citations: citations, interactionId: interactionId)
                    }
                }
    }
}
