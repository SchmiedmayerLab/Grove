//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import GeneratedOpenAIClient
import GroveLLM
import OpenAPIRuntime
import OpenAPIURLSession


/// Shared OpenAPI `Client` construction for OpenAI-compatible chat and embedding callers.
@available(iOS 18, macOS 15, watchOS 11, *)
enum OpenAICompatibleClientFactory {
    /// Builds a `Client` with bearer auth, retry policy, and optional extra middlewares.
    ///
    /// - Parameters:
    ///   - serverURL: OpenAI-compatible base URL.
    ///   - authToken: Token source for `BearerAuthMiddleware`.
    ///   - keychainStorage: Keychain access when `authToken` is `.keychain`; ignored otherwise.
    ///   - retryPolicy: Retry policy applied by `RetryMiddleware`.
    ///   - timeout: Request timeout used when creating a default `URLSession` transport.
    ///   - transport: Optional injectable transport for tests; defaults to `URLSessionTransport`.
    ///   - middlewares: Extra middlewares appended after auth and retry.
    /// - Returns: A configured OpenAPI client.
    static func makeClient(
        serverURL: URL,
        authToken: RemoteLLMInferenceAuthToken,
        keychainStorage: LLMCredentialStorage?,
        retryPolicy: RetryPolicy,
        timeout: TimeInterval,
        transport: (any ClientTransport)? = nil,
        middlewares: [any ClientMiddleware] = []
    ) -> Client {
        let resolvedTransport: any ClientTransport
        if let transport {
            resolvedTransport = transport
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = timeout
            resolvedTransport = URLSessionTransport(
                configuration: .init(session: URLSession(configuration: configuration))
            )
        }

        return Client(
            serverURL: serverURL,
            transport: resolvedTransport,
            middlewares: [
                BearerAuthMiddleware(authToken: authToken, keychainStorage: keychainStorage),
                RetryMiddleware(policy: retryPolicy)
            ] + middlewares
        )
    }
}
