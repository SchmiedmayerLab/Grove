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


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMOpenAILikeSession {
    /// Based on the input prompt, generate the output via the OpenAI API.
    ///
    /// - Parameters:
    ///   - continuationObserver: The generation receiving output and tracking invocation cancellation.
    func _generate( // swiftlint:disable:this identifier_name function_body_length cyclomatic_complexity
        with continuationObserver: OpenAIGeneration
    ) async {
        // Check if the generation has been cancelled
        if continuationObserver.isCancelled {
            Self.logger.warning("GroveLLMOpenAI: Generation cancelled by the user.")
            return
        }

        /// Groups every context entity produced by this single user → LLM interaction.
        let interactionId = LLMInteractionId()

        await MainActor.run {
            self.state = .generating
        }

        while true {
            // Check if the generation has been cancelled
            if continuationObserver.isCancelled {
                Self.logger.warning("GroveLLMOpenAI: Generation cancelled by the user.")
                break
            }

            var llmStreamResults: [Int: LLMOpenAIStreamResult] = [:]
            
            do {
                let query = try await openAIChatQuery()
                let response = try await openAiClient.request(for: continuationObserver) { try await $0.createChatCompletion(query) }

                if case let .undocumented(statusCode: statusCode, payload) = response {
                    let llmError = handleErrorCode(statusCode)
                    #if DEBUG
                    if let body = payload.body, case let .known(length) = body.length {
                        let buffer = try await Data(collecting: body, upTo: Int(length))
                        let text = String(data: buffer, encoding: .utf8) ?? "<non-UTF8 body>"
                        Self.logger.warning("GroveLLMOpenAI: Undocumented request body:\n\(text)")
                    }
                    #endif
                    await finishGenerationWithError(llmError, on: continuationObserver)
                    return
                }

                let chatStream = try response.ok.body.text_event_hyphen_stream.asDecodedServerSentEvents()
                var providerStream = OpenAIChatStream()
                for try await event in chatStream {
                    // Check if the generation has been cancelled
                    if continuationObserver.isCancelled {
                        Self.logger.warning("GroveLLMOpenAI: Generation cancelled by the user.")

                        // cleanup, discard any results so that we don't perform function calls
                        llmStreamResults = [:]
                        break
                    }

                    guard let data = event.data else {
                        continue
                    }
                    guard let chunk = try providerStream.consume(data, for: continuationObserver) else {
                        break
                    }
                    var content: String?
                    for choice in chunk.choices {
                        let result = llmStreamResults[choice.index, default: .init()].append(choice: choice)
                        if content == nil, result.role == .assistant, let delta = result.deltaContent, !delta.isEmpty {
                            content = delta
                        }
                    }
                    guard let content else {
                        continue
                    }

                    // Automatically inject the yielded string piece into the `LLMLocal/context`
                    if schema.injectIntoContext {
                        await MainActor.run {
                            context.append(assistantOutputDelta: content, isComplete: false, interactionId: interactionId)
                        }
                    }

                    // Yield string piece into continuation
                    continuationObserver.text(content)
                }
                
                if continuationObserver.isCancelled || Task.isCancelled {
                    throw CancellationError()
                }
                try providerStream.finish(continuationObserver)
                if providerStream.incomplete { llmStreamResults.removeAll() }
                if schema.injectIntoContext {
                    await MainActor.run {
                        context.markAssistantOutputCompleted()
                    }
                }
            } catch where RetryMiddleware.isCancellation(error) {
                await cleanUpInterruptedStreaming(interactionId: interactionId)
                continuationObserver.finish(throwing: CancellationError())
                break
            } catch let error as ClientError {
                Self.logger.error("GroveLLMOpenAI: Connectivity Issues with the OpenAI API: \(error)")
                await finishGenerationWithError(LLMOpenAIError.connectivityIssues(error), on: continuationObserver)
                return
            } catch let error as LLMOpenAIError {
                await cleanUpInterruptedStreaming(interactionId: interactionId)
                Self.logger.error("GroveLLMOpenAI: \(error.localizedDescription)")
                await finishGenerationWithError(error, on: continuationObserver)
                return
            } catch {
                Self.logger.error("GroveLLMOpenAI: Unknown Generation error occurred - \(error)")
                await finishGenerationWithError(LLMOpenAIError.generationError, on: continuationObserver)
                return
            }

            let functionCalls = llmStreamResults.values.compactMap { $0.functionCall }.flatMap { $0 }

            // Exit the while loop if we don't have any function calls
            guard !functionCalls.isEmpty else {
                await checkForActiveToolCalls()
                break
            }
            
            // Inject the requested function calls into the LLM context
            let functionCallContext: [LLMContextEntity.ToolCall] = functionCalls.compactMap { functionCall in
                guard let functionCallID = functionCall.id,
                      let functionCallName = functionCall.name else {
                    return nil
                }

                return .init(id: functionCallID, name: functionCallName, arguments: functionCall.arguments ?? "")
            }
            await MainActor.run {
                context.append(toolCalls: functionCallContext, interactionId: interactionId)
            }

            // Parallel function call execution
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for functionCall in functionCalls {
                        group.addTask {
                            // Check if the function call execution has been cancelled
                            if continuationObserver.isCancelled {
                                Self.logger.warning("GroveLLMOpenAI: Function call execution cancelled by the user.")
                                return
                            }
                            
                            let functionCallResponse = try? await self.callFunction(
                                availableFunctions: self.schema.functions,
                                functionCallArgs: functionCall,
                                failureHandling: .returnErrorInResponse
                            )

                            guard let functionCallResponse = functionCallResponse else {
                                Self.logger.warning("GroveLLMOpenAI: callFunction() threw an error.")
                                return
                            }

                            await MainActor.run {
                                self.context.append(
                                    toolCallResponse: functionCallResponse.response,
                                    for: functionCallResponse.functionName,
                                    withId: functionCallResponse.functionID,
                                    interactionId: interactionId
                                )
                            }
                        }
                    }
                    
                    try await group.waitForAll()
                }
            } catch {
                // The calls report their own failures, so only cancellation reaches this point.
                continuationObserver.finish(throwing: CancellationError())
                return
            }
        }
        
        await MainActor.run {
            self.state = .ready
        }
    }
}
