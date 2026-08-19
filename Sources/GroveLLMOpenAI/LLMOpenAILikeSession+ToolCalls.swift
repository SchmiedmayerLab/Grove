//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveLLM
import Synchronization


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMOpenAILikeSession {
    /// What stands in for a tool call that never produced a result, so the turn still adds up.
    private static var unansweredToolCallResponse: String {
        "Error - the tool call did not complete."
    }

    /// The announced calls that no response came back for.
    ///
    /// Split out from the execution so the rule can be checked on its own: every call the model was told about
    /// has to be accounted for, and a call without an id cannot be replayed to the server anyway.
    package static func unansweredCalls(
        among functionCalls: [LLMOpenAIStreamResult.FunctionCall],
        answered: Set<String>
    ) -> [LLMOpenAIStreamResult.FunctionCall] {
        functionCalls.filter { call in
            guard let id = call.id, !id.isEmpty else {
                return false
            }
            return !answered.contains(id)
        }
    }
    /// Records the requested tool calls and runs them, reporting whether the conversation may continue.
    ///
    /// - Returns: `false` when the turn has to stop, which is when a call failed unexpectedly.
    func runToolCalls(
        _ functionCalls: [LLMOpenAIStreamResult.FunctionCall],
        with continuationObserver: ContinuationObserver<String, any Error>,
        interactionId: LLMInteractionId
    ) async -> Bool {
        let toolCalls: [LLMContextEntity.ToolCall] = functionCalls.compactMap { functionCall in
            guard let name = functionCall.name else {
                return nil
            }
            return .init(id: functionCall.id ?? "", name: name, arguments: functionCall.arguments ?? "")
        }
        await MainActor.run {
            context.append(toolCalls: toolCalls, interactionId: interactionId)
        }

        do {
            try await executeFunctionCalls(functionCalls, with: continuationObserver, interactionId: interactionId)
        } catch {
            // Stop the inference in case of an unexpected error during a function call.
            abandonServerSideConversation()
            return false
        }
        if continuationObserver.isCancelled {
            // The tool calls were announced to the server but never answered. Continuing that conversation would
            // have the next request rejected for the missing outputs, so it is started over instead.
            abandonServerSideConversation()
        }
        return true
    }

    /// Runs every requested tool call at once, appending each result to the context as it lands.
    ///
    /// Every announced call is answered, including the ones that were cancelled or failed. The model was told the
    /// calls exist, so a later request replaying this turn has to carry an output for each of them — a
    /// `function_call` without its `function_call_output` is rejected outright, and would keep being rejected on
    /// every retry, which takes the conversation down for good rather than just losing one answer.
    private func executeFunctionCalls(
        _ functionCalls: [LLMOpenAIStreamResult.FunctionCall],
        with continuationObserver: ContinuationObserver<String, any Error>,
        interactionId: LLMInteractionId
    ) async throws {
        let answered = try await withThrowingTaskGroup(of: String?.self, returning: Set<String>.self) { group in
            for functionCall in functionCalls {
                group.addTask {
                    guard !continuationObserver.isCancelled else {
                        return nil
                    }
                    let response = try? await self.callFunction(
                        availableFunctions: self.schema.functions,
                        functionCallArgs: functionCall,
                        failureHandling: .returnErrorInResponse
                    )
                    guard let response else {
                        Self.logger.warning("GroveLLMOpenAI: callFunction() threw an error.")
                        return nil
                    }
                    await MainActor.run {
                        self.context.append(
                            toolCallResponse: response.response,
                            for: response.functionName,
                            withId: response.functionID,
                            interactionId: interactionId
                        )
                    }
                    return response.functionID
                }
            }
            return try await group.reduce(into: Set<String>()) { answered, id in
                if let id {
                    answered.insert(id)
                }
            }
        }

        let unanswered = Self.unansweredCalls(among: functionCalls, answered: answered)
        guard !unanswered.isEmpty else {
            return
        }
        Self.logger.warning("GroveLLMOpenAI: \(unanswered.count) tool call(s) went unanswered; reporting them as such.")
        await MainActor.run {
            for call in unanswered {
                context.append(
                    toolCallResponse: Self.unansweredToolCallResponse,
                    for: call.name ?? "",
                    withId: call.id ?? "",
                    interactionId: interactionId
                )
            }
        }
    }
}
