//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

import Foundation
import GeneratedOpenAIClient
import GroveLLM
import OpenAPIRuntime
import Synchronization


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMOpenAILikeSession {
    /// Generates a response using the OpenAI Responses API (`POST /v1/responses`).
    ///
    /// The Responses API equivalent of ``_generate(with:)``: it consumes the SSE event stream, surfacing text deltas,
    /// reasoning summaries, and function calls, and carries multi-turn state via `previous_response_id`.
    func _generateWithResponses( // swiftlint:disable:this identifier_name
        with continuationObserver: ContinuationObserver<String, any Error>
    ) async {
        guard !continuationObserver.isCancelled else {
            Self.logger.warning("GroveLLMOpenAI: Generation cancelled by the user.")
            return
        }

        /// Groups every context entity produced by this single user → LLM interaction.
        let interactionId = LLMInteractionId()

        await MainActor.run {
            self.state = .generating
        }

        while true {
            guard !continuationObserver.isCancelled else {
                Self.logger.warning("GroveLLMOpenAI: Generation cancelled by the user.")
                await cleanUpInterruptedStreaming(interactionId: interactionId)
                break
            }

            let functionCalls: [LLMOpenAIStreamResult.FunctionCall]
            do {
                functionCalls = try await respond(with: continuationObserver, interactionId: interactionId)
            } catch let error as ResponsesGenerationError {
                await cleanUpInterruptedStreaming(interactionId: interactionId)
                await finishGenerationWithError(error.llmError, on: continuationObserver.continuation)
                return
            } catch {
                Self.logger.error("GroveLLMOpenAI: Unknown Generation error occurred - \(error)")
                await cleanUpInterruptedStreaming(interactionId: interactionId)
                await finishGenerationWithError(LLMOpenAIError.generationError, on: continuationObserver.continuation)
                return
            }

            // Exit the loop if the model didn't ask for any tools.
            guard !functionCalls.isEmpty else {
                await checkForActiveToolCalls()
                break
            }

            guard await runToolCalls(functionCalls, with: continuationObserver, interactionId: interactionId) else {
                return
            }
        }

        await MainActor.run {
            self.state = .ready
        }
    }

    /// Produces a single response, streamed where the server manages it.
    ///
    /// A stream that fails before yielding anything is retried unstreamed, so that a gateway implementing
    /// `/v1/responses` without streaming still answers. Nothing has reached the user at that point, so the retry
    /// cannot duplicate output; a stream that breaks *after* output has arrived is not retried, and what was
    /// received stands.
    private func respond(
        with continuationObserver: ContinuationObserver<String, any Error>,
        interactionId: LLMInteractionId
    ) async throws -> [LLMOpenAIStreamResult.FunctionCall] {
        do {
            return try await streamResponse(with: continuationObserver, interactionId: interactionId)
        } catch let error as ResponsesGenerationError {
            guard platform.configuration.streamingFallback,
                  !error.hasProducedOutput,
                  !error.hasCommittedConversation,
                  !continuationObserver.isCancelled,
                  Self.isWorthRetryingWithoutStreaming(error.llmError) else {
                throw error
            }
            Self.logger.warning(
                "GroveLLMOpenAI: Streaming the response failed (\(error.llmError.localizedDescription)); retrying without streaming."
            )
            await cleanUpInterruptedStreaming(interactionId: interactionId)
            return try await fetchResponseWithoutStreaming(with: continuationObserver, interactionId: interactionId)
        }
    }

    /// Consumes a single streamed response, returning the function calls the model requested, if any.
    private func streamResponse( // swiftlint:disable:this function_body_length cyclomatic_complexity
        with continuationObserver: ContinuationObserver<String, any Error>,
        interactionId: LLMInteractionId
    ) async throws -> [LLMOpenAIStreamResult.FunctionCall] {
        var functionCalls: [LLMOpenAIStreamResult.FunctionCall] = []
        var hasProducedOutput = false
        var hasCommittedConversation = false
        do {
            let response = try await openAiClient.createResponse(openAIResponsesQuery())
            if case let .undocumented(statusCode: statusCode, payload) = response {
                let llmError = handleErrorCode(statusCode)
                #if DEBUG
                if let body = payload.body, case let .known(length) = body.length {
                    let buffer = try await Data(collecting: body, upTo: Int(length))
                    let text = String(data: buffer, encoding: .utf8) ?? "<non-UTF8 body>"
                    Self.logger.warning("GroveLLMOpenAI: Undocumented response body:\n\(text)")
                }
                #endif
                throw ResponsesGenerationError(llmError: llmError)
            }

            let eventStream = try response.ok.body.text_event_hyphen_stream.asDecodedServerSentEvents()

            for try await event in eventStream {
                if continuationObserver.isCancelled {
                    Self.logger.warning("GroveLLMOpenAI: Generation cancelled by the user.")
                    functionCalls = []
                    break
                }
                guard let jsonData = event.data?.data(using: .utf8),
                      let payload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                      let rawType = payload["type"] as? String else {
                    continue
                }
                guard let eventType = ResponseStreamEventType(rawValue: rawType) else {
                    Self.logger.debug("GroveLLMOpenAI: Encountered unhandled event: \(rawType)")
                    continue
                }

                switch eventType {
                case .responseCreated:
                    await MainActor.run {
                        context.beginAssistantThinkingPlaceholder(with: interactionId)
                    }
                case .responseOutputTextDelta, .responseRefusalDelta:
                    // A refusal is the model's user-facing answer; it streams and surfaces exactly like output text.
                    guard let delta = payload["delta"] as? String else {
                        continue
                    }
                    // The first content token marks the end of the thinking phase.
                    await MainActor.run {
                        context.completeAssistantThinkingStreaming(for: interactionId)
                        if schema.injectIntoContext {
                            context.append(assistantOutputDelta: delta, isComplete: false, interactionId: interactionId)
                        }
                    }
                    continuationObserver.continuation.yield(delta)
                    hasProducedOutput = true
                case .responseOutputTextDone, .responseRefusalDone:
                    if schema.injectIntoContext {
                        await MainActor.run {
                            context.markAssistantOutputCompleted()
                        }
                    }
                case .responseOutputItemDone:
                    if let item = payload["item"] as? [String: Any], item["type"] as? String == "message" {
                        let citations = Self.citations(fromOutputItem: item)
                        if !citations.isEmpty {
                            await MainActor.run {
                                context.append(citations: citations, interactionId: interactionId)
                            }
                        }
                    }
                    // Function calls stream across multiple events, but the `function_call_arguments` deltas carry only an
                    // `item_id` and the partial argument string — notably not the function name, despite the spec marking it
                    // required. `response.output_item.done` instead carries the finalized item, which for a function call has
                    // `call_id`, `name`, and the complete `arguments` JSON in one place.
                    guard let item = payload["item"] as? [String: Any], item["type"] as? String == "function_call" else {
                        continue
                    }
                    guard let callId = item["call_id"] as? String,
                          let name = item["name"] as? String,
                          let arguments = item["arguments"] as? String else {
                        Self.logger.warning("GroveLLMOpenAI: Incomplete function_call output item: \(item)")
                        continue
                    }
                    functionCalls.append(.init(name: name, id: callId, arguments: arguments))
                case .responseReasoningSummaryPartAdded:
                    // Idempotent against the placeholder created above; only starts a new entity once the previous part
                    // has completed, i.e. when a subsequent reasoning part begins.
                    await MainActor.run {
                        context.beginAssistantThinkingPlaceholder(with: interactionId)
                    }
                case .responseReasoningSummaryTextDelta:
                    guard let delta = payload["delta"] as? String else {
                        continue
                    }
                    await MainActor.run {
                        context.append(assistantThinkingDelta: delta, interactionId: interactionId)
                    }
                case .responseReasoningSummaryTextDone, .responseReasoningSummaryPartDone:
                    await MainActor.run {
                        context.completeAssistantThinkingStreaming(for: interactionId)
                    }
                case .responseCompleted, .responseIncomplete:
                    // An incomplete response — e.g. the output token limit was reached — still ends the stream with
                    // a continuable response the server retains; it differs from `completed` only in being truncated.
                    if eventType == .responseIncomplete {
                        Self.logger.warning("GroveLLMOpenAI: Response ended incomplete; the output may be truncated.")
                    }
                    if let response = payload["response"] as? [String: Any], let responseId = response["id"] as? String {
                        // The server now holds everything this request carried; only re-send what comes after it.
                        self.responsesConversation.withLock { state in
                            state.commitPendingContext(responseId: responseId)
                        }
                        hasCommittedConversation = true
                    }
                case .responseFailed:
                    let error = (payload["response"] as? [String: Any])?["error"] as? [String: Any]
                    let message = error?["message"] as? String ?? "Unknown error"
                    Self.logger.error("GroveLLMOpenAI: Response failed: \(message)")
                    throw ResponsesGenerationError(
                        llmError: LLMOpenAIError.generationError,
                        hasProducedOutput: hasProducedOutput,
                        hasCommittedConversation: hasCommittedConversation
                    )
                case .error:
                    let message = payload["message"] as? String ?? "Unknown error"
                    Self.logger.error("GroveLLMOpenAI: Stream reported an error: \(message)")
                    throw ResponsesGenerationError(
                        llmError: LLMOpenAIError.generationError,
                        hasProducedOutput: hasProducedOutput,
                        hasCommittedConversation: hasCommittedConversation
                    )
                default:
                    // An event that either needs no handling, or that we don't support.
                    break
                }
            }

            // The stream ended. Make sure no thinking placeholder is left dangling — e.g. when the model responded with only
            // a function call and no reasoning summary parts. If the stream ended due to cancellation, drop the unfinished
            // placeholder entirely instead of marking it complete.
            if continuationObserver.isCancelled {
                await cleanUpInterruptedStreaming(interactionId: interactionId)
            } else {
                await MainActor.run {
                    context.completeAssistantThinkingStreaming(for: interactionId)
                }
            }
            return functionCalls
        } catch let error as ResponsesGenerationError {
            throw error
        } catch let error as ClientError {
            Self.logger.error("GroveLLMOpenAI: Connectivity Issues with the OpenAI API: \(error)")
            throw ResponsesGenerationError(
                llmError: LLMOpenAIError.connectivityIssues(error),
                hasProducedOutput: hasProducedOutput,
                hasCommittedConversation: hasCommittedConversation
            )
        } catch let error as LLMOpenAIError {
            // Passed through as-is: schema extraction already wraps its own failures, so re-wrapping here would
            // relabel every other request-building error as a function-call problem.
            Self.logger.error("GroveLLMOpenAI: \(error.localizedDescription)")
            throw ResponsesGenerationError(
                llmError: error,
                hasProducedOutput: hasProducedOutput,
                hasCommittedConversation: hasCommittedConversation
            )
        } catch {
            // Anything else — a body that decoded as JSON because the server answered a streamed request without
            // streaming, a connection that died before the first event — still has to arrive as a
            // `ResponsesGenerationError`, or the caller cannot tell that the unstreamed retry is worth attempting.
            Self.logger.error("GroveLLMOpenAI: Streaming the response failed - \(error)")
            throw ResponsesGenerationError(
                        llmError: LLMOpenAIError.generationError,
                        hasProducedOutput: hasProducedOutput,
                        hasCommittedConversation: hasCommittedConversation
                    )
        }
    }

    /// Forgets the conversation the server is holding, so the next request replays the context instead of
    /// continuing from a response whose tool calls were never answered.
    func abandonServerSideConversation() {
        responsesConversation.withLock { state in
            state = ResponsesConversationState()
        }
    }

    /// Restores the context after a cancelled or failed stream: unfinished thinking placeholders vanish,
    /// and a partially streamed answer is finalized — it is all the user will get.
    func cleanUpInterruptedStreaming(interactionId: LLMInteractionId) async {
        await MainActor.run {
            context.removeIncompleteAssistantThinking(for: interactionId)
            if schema.injectIntoContext {
                context.markAssistantOutputCompleted()
            }
        }
    }
}


/// Carries an ``LLMOpenAIError`` out of the streaming loop, so that the caller performs the cleanup in one place.
@available(iOS 18, macOS 15, watchOS 11, *)
struct ResponsesGenerationError: Error {
    let llmError: any LLMError
    /// Whether any output had already reached the user when this failed, which rules out retrying the request.
    var hasProducedOutput = false
    /// Whether the server had already taken ownership of this request's input.
    ///
    /// Past the commit the input is server-side state; retrying would send an empty input against a
    /// `previous_response_id`, which asks the model to answer nothing.
    var hasCommittedConversation = false
}


/// The server-sent event types emitted when streaming an OpenAI Responses API response.
@available(iOS 18, macOS 15, watchOS 11, *)
private enum ResponseStreamEventType: String, Sendable, Hashable {
    // MARK: Response Lifecycle
    /// Response object created, status `in_progress`.
    case responseCreated = "response.created"
    /// Generation has started.
    case responseInProgress = "response.in_progress"
    /// Generation finished successfully.
    case responseCompleted = "response.completed"
    /// Generation failed; check the `error` field on the response.
    case responseFailed = "response.failed"
    /// Generation stopped early, e.g. because the output token limit was reached.
    case responseIncomplete = "response.incomplete"
    /// Response is queued for processing (background mode).
    case responseQueued = "response.queued"

    // MARK: Output Items
    /// A new item was appended to the response's `output` array (message, function_call, reasoning, …).
    case responseOutputItemAdded = "response.output_item.added"
    /// An output item has been finalized.
    case responseOutputItemDone = "response.output_item.done"

    // MARK: Content Parts
    /// A new content part was added to a message item's `content` array.
    case responseContentPartAdded = "response.content_part.added"
    /// A content part has been finalized.
    case responseContentPartDone = "response.content_part.done"

    // MARK: Text Output
    /// An incremental text token delta.
    case responseOutputTextDelta = "response.output_text.delta"
    /// A citation or annotation was added to the text output.
    case responseOutputTextAnnotationAdded = "response.output_text.annotation.added"
    /// The text content part is complete.
    case responseOutputTextDone = "response.output_text.done"

    // MARK: Refusal
    /// An incremental refusal text delta.
    case responseRefusalDelta = "response.refusal.delta"
    /// The refusal content is complete.
    case responseRefusalDone = "response.refusal.done"

    // MARK: Function Calling
    /// An incremental delta of the JSON-encoded function call arguments.
    case responseFunctionCallArgumentsDelta = "response.function_call_arguments.delta"
    /// The function call arguments are complete.
    case responseFunctionCallArgumentsDone = "response.function_call_arguments.done"

    // MARK: Custom Tool Calls (MCP, etc.)
    /// An incremental input delta for a custom tool call.
    case responseCustomToolCallInputDelta = "response.custom_tool_call_input.delta"
    /// The custom tool call input is complete.
    case responseCustomToolCallInputDone = "response.custom_tool_call_input.done"

    // MARK: File Search
    /// A file search tool call has started.
    case responseFileSearchCallInProgress = "response.file_search_call.in_progress"
    /// The file search tool call is actively searching.
    case responseFileSearchCallSearching = "response.file_search_call.searching"
    /// The file search tool call has completed with results.
    case responseFileSearchCallCompleted = "response.file_search_call.completed"

    // MARK: Code Interpreter
    /// A code interpreter tool call has started.
    case responseCodeInterpreterCallInProgress = "response.code_interpreter_call.in_progress"
    /// An incremental delta of the generated code.
    case responseCodeInterpreterCallCodeDelta = "response.code_interpreter_call.code.delta"
    /// The generated code is complete.
    case responseCodeInterpreterCallCodeDone = "response.code_interpreter_call.code.done"
    /// The code interpreter is executing the generated code.
    case responseCodeInterpreterCallInterpreting = "response.code_interpreter_call.interpreting"
    /// The code interpreter tool call has completed execution.
    case responseCodeInterpreterCallCompleted = "response.code_interpreter_call.completed"

    // MARK: Web Search
    /// A web search tool call has started.
    case responseWebSearchCallInProgress = "response.web_search_call.in_progress"
    /// The web search tool call is actively searching.
    case responseWebSearchCallSearching = "response.web_search_call.searching"
    /// The web search tool call has completed with results.
    case responseWebSearchCallCompleted = "response.web_search_call.completed"

    // MARK: Reasoning
    /// A reasoning summary part was added.
    case responseReasoningSummaryPartAdded = "response.reasoning_summary_part.added"
    /// A reasoning summary part has been finalized.
    case responseReasoningSummaryPartDone = "response.reasoning_summary_part.done"
    /// An incremental delta of the reasoning summary text.
    case responseReasoningSummaryTextDelta = "response.reasoning_summary_text.delta"
    /// The reasoning summary text is complete.
    case responseReasoningSummaryTextDone = "response.reasoning_summary_text.done"

    // MARK: Error
    /// An error occurred during streaming.
    case error = "error"
}
