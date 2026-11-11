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
    /// Set up the OpenAI LLM execution client.
    ///
    /// - Parameters:
    ///   - continuationObserver: A `ContinuationObserver` that tracks a Swift `AsyncThrowingStream` continuation for cancellation.
    /// - Returns: `true` if the setup was successful, `false` otherwise.
    func setup(with continuationObserver: ContinuationObserver<String, any Error>) async -> Bool {
        await MainActor.run {
            self.state = .loading
        }
        
        if !self.initializeClient() {
            return false
        }

        if continuationObserver.isCancelled {
            Self.logger.warning("GroveLLMOpenAI: Generation cancelled by the user.")
            await MainActor.run {
                self.state = .ready     // as the session is set up
            }
            return false
        }

        // Check access to the specified OpenAI model
        if self.schema.parameters.modelAccessTest,
           await !self.modelAccessTest(continuation: continuationObserver.continuation) {
            return false
        }
        
        await MainActor.run {
            self.state = .ready
        }
        return true
    }

    /// Initialize the OpenAI OpenAPI client.
    ///
    /// - Returns: `true` if the client could be initialized, `false` otherwise.
    private func initializeClient() -> Bool {
        self.openAiClient = OpenAICompatibleClientFactory.makeClient(
            serverURL: self.platform.configuration.serverUrl,
            authToken: schema.parameters.overwritingAuthToken ?? platform.configuration.authToken,
            keychainStorage: keychainStorage,
            retryPolicy: self.platform.configuration.retryPolicy,
            timeout: platform.configuration.timeout,
            middlewares: platform.configuration.middlewares
        )
        return true
    }

    /// Tests access to the OpenAI model.
    ///
    /// - Parameters:
    ///   - continuation: A Swift `AsyncThrowingStream` that streams the generated output.
    /// - Returns: `true` if the model access test was successful, `false` otherwise.
    private func modelAccessTest(continuation: AsyncThrowingStream<String, any Error>.Continuation) async -> Bool {
        do {
            if case let .undocumented(statusCode, _) = try await openAiClient
                .retrieveModel(.init(path: .init(model: schema.parameters.modelType.rawValue))) {
                let llmError = handleErrorCode(statusCode)
                await finishGenerationWithError(llmError, on: continuation)
                return false
            }
            return true
        } catch let error as ClientError {
            Self.logger.error("GroveLLMOpenAI: Model access check - Connectivity Issues with the OpenAI API: \(error)")
            await finishGenerationWithError(LLMOpenAIError.connectivityIssues(error), on: continuation)
        } catch {
            Self.logger.error("GroveLLMOpenAI: Model access check - unknown error occurred")
            await finishGenerationWithError(LLMOpenAIError.generationError, on: continuation)
        }
        return false
    }
}
