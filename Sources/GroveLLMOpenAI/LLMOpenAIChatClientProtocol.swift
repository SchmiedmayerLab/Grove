//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GeneratedOpenAIClient


@available(iOS 18, macOS 15, watchOS 11, *)
internal protocol LLMOpenAIChatClientProtocol: Sendable {
    /// Whether the client reports each transport attempt itself.
    ///
    /// A `Client` does, because the session builds it on a `RetryMiddleware.Transport`. Any other client counts as
    /// one attempt per request.
    var observesTransportAttempts: Bool { get }

    func createChatCompletion(_ input: Operations.createChatCompletion.Input) async throws -> Operations.createChatCompletion.Output

    func createResponse(_ input: Operations.createResponse.Input) async throws -> Operations.createResponse.Output
    
    func retrieveModel(_ input: Operations.retrieveModel.Input) async throws -> Operations.retrieveModel.Output
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension Client: LLMOpenAIChatClientProtocol {
    var observesTransportAttempts: Bool { true }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMOpenAIChatClientProtocol {
    var observesTransportAttempts: Bool { false }

    func request<Output: Sendable>(
        for generation: OpenAIGeneration,
        send: (Self) async throws -> Output
    ) async throws -> Output {
        try RetryMiddleware.checkCancellation()
        generation.beginRequest()
        if !observesTransportAttempts {
            generation.dispatch()
        }
        return try await generation.observingAttempts {
            try await send(self)
        }
    }
}
