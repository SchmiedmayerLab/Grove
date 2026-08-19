//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

package import Atomics
import Foundation
package import GroveFoundation
package import GroveLLM


@available(iOS 18, macOS 15, watchOS 11, *)
package protocol ToolCallLLMSession: LLMSession {
    // Logger is required for functions in the ToolCallLLMSession extension
    static var logger: Logger { get }
    /// The state the LLMSession should return to after completing a tool/function call.
    var toolCallCompletionState: LLMState { get }
    /// Counter to track how many tool (function) calls are currently in progress.
    var toolCallCounter: ManagedAtomic<Int> { get }

    /// Attempts to call a function requested by the LLM.
    /// - Parameters:
    ///   - availableFunctions: A dictionary mapping function names to their corresponding implementations (`LLMTool`).
    ///   - functionCallArgs: The raw function call request provided by the LLM, including function name, ID, and arguments.
    ///   - failureHandling: Strategy for handling errors if the function call fails (e.g. stop inference, or append error to context).
    ///
    /// - Returns: A `ToolCallResponse` containing the function call ID, name, and optional response.
    ///
    /// - Throws: An `LLMError` if the function name, arguments, or execution fails.
    func callFunction(
        availableFunctions: [String: any LLMTool],
        functionCallArgs: LLMOpenAIStreamResult.FunctionCall,
        failureHandling: ToolCallLLMSessionTypes.ToolCallFailureHandling
    ) async throws -> ToolCallLLMSessionTypes.ToolCallResponse
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ToolCallLLMSession {
    // Handles function calls with configurable failure behavior.
    package func callFunction(
        availableFunctions: [String: any LLMTool],
        functionCallArgs: LLMOpenAIStreamResult.FunctionCall,
        failureHandling: ToolCallLLMSessionTypes.ToolCallFailureHandling
    ) async throws -> ToolCallLLMSessionTypes.ToolCallResponse {
        do {
            return try await _callFunction(availableFunctions: availableFunctions, functionCallArgs: functionCallArgs)
        } catch let error as any LLMError {
            switch failureHandling {
            case .throwAndStopInference(let continuationObserver):
                await self.finishGenerationWithError(
                    error,
                    on: continuationObserver.continuation
                )
            case .returnErrorInResponse:
                let errorMessage: String
                switch error {
                case LLMOpenAIError.invalidToolCallName:
                    errorMessage = "Error - invalid function call name"
                case LLMOpenAIError.invalidToolCallArguments(let err):
                    errorMessage = "Error - invalid function call arguments: \(err.localizedDescription)"
                case LLMOpenAIError.toolCallError(let err):
                    errorMessage = "Error - function call execution error: \(err.localizedDescription)"
                default:
                    errorMessage = "Error - unexpected: \(error.localizedDescription)"
                }

                return ToolCallLLMSessionTypes.ToolCallResponse(
                        functionID: functionCallArgs.id ?? "",
                        functionName: functionCallArgs.name ?? "",
                        response: errorMessage
                )
            case .throwError:
                break
            }
            
            throw error
        }
    }
    
    /// Executes a function call.
    ///
    /// This method validates the function name and arguments, injects them into the target function,
    /// executes it asynchronously, and returns the response. It also ensures the tool call counter
    /// is incremented/decremented appropriately for tracking concurrent executions.
    ///
    /// - Throws:
    ///   - `LLMOpenAIError.invalidToolCallName` if the function name or ID is missing, or the function is not found.
    ///   - `LLMOpenAIError.invalidToolCallArguments` if argument decoding or parameter injection fails.
    ///   - `LLMOpenAIError.toolCallError` if the function itself throws during execution.
    private func _callFunction(
        availableFunctions: [String: any LLMTool],
        functionCallArgs: LLMOpenAIStreamResult.FunctionCall,
    ) async throws -> ToolCallLLMSessionTypes.ToolCallResponse {
        await self.incrementToolCallCounter()
        guard let functionName = functionCallArgs.name,
              let functionID = functionCallArgs.id,
              let functionArgument = functionCallArgs.arguments?.data(using: .utf8),
              let function = availableFunctions[functionName] else {
            Self.logger.error("ToolCallLLMSession: Couldn't find the requested function to call")
            await self.decrementToolCallCounter()
            throw LLMOpenAIError.invalidToolCallName
        }
        
        // The arguments belong to this invocation, not to the shared function, so nothing here keeps concurrent
        // calls to the same function from running at the same time.
        let arguments: LLMToolArguments
        do {
            arguments = try function.arguments(from: functionArgument)
        } catch {
            Self.logger.error("ToolCallLLMSession: Invalid function call arguments - \(error)")
            await self.decrementToolCallCounter()
            throw LLMOpenAIError.invalidToolCallArguments(error)
        }

        let functionCallResponseStr: String?
        do {
            // Errors thrown by the functions are surfaced to the user as an LLM generation error
            functionCallResponseStr = try await function.execute(with: arguments)
        } catch {
            Self.logger.error("ToolCallLLMSession: Function call execution error - \(error)")
            await self.decrementToolCallCounter()
            throw LLMOpenAIError.toolCallError(error)
        }
        
        await self.decrementToolCallCounter()
        
        let defaultResponse = "Function call to \(functionName) succeeded, function intentionally didn't respond anything."
        
        // Return `defaultResponse` in case of `nil` or empty return of the function call
        return ToolCallLLMSessionTypes.ToolCallResponse(
            functionID: functionID,
            functionName: functionName,
            response: (functionCallResponseStr?.isEmpty ?? true)
                ? defaultResponse
                : functionCallResponseStr ?? ""
        )
    }
    
    /// Checks if there are active tool calls and updates the state if needed.
    func checkForActiveToolCalls() async {
        if toolCallCounter.load(ordering: .sequentiallyConsistent) == 0 {
            await MainActor.run {
                self.state = toolCallCompletionState
            }
        }
    }

    /// Safely increments the tool call counter and updates the state if needed.
    private func incrementToolCallCounter(by value: Int = 1) async {
        if toolCallCounter.loadThenWrappingIncrement(
            by: value,
            ordering: .sequentiallyConsistent
        ) == 0 {
            await MainActor.run {
                self.state = .callingTools
            }
        }
    }

    /// Safely decrements the tool call counter and updates the state if needed.
    private func decrementToolCallCounter() async {
        if toolCallCounter.loadThenWrappingDecrement(
            by: 1,
            ordering: .sequentiallyConsistent
        ) == 1 {
            await MainActor.run {
                self.state = toolCallCompletionState
            }
        }
    }
}
