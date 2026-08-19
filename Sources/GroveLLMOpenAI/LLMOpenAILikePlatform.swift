//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GeneratedOpenAIClient
import Grove
import GroveFoundation
#if canImport(Security)
public import GroveKeychainStorage
#endif
public import GroveLLM


/// A `LLMPlatform` that is interoperable with the OpenAI API.
@available(iOS 18, macOS 15, watchOS 11, *)
public final class LLMOpenAILikePlatform<PlatformDefinition: LLMOpenAILikePlatformDefinition>: LLMPlatform, @unchecked Sendable {
    public typealias Schema = LLMOpenAILikeSchema<PlatformDefinition>
    public typealias Session = LLMOpenAILikeSession<PlatformDefinition>

    /// Configuration of the platform.
    public let configuration: LLMOpenAILikePlatformConfiguration<PlatformDefinition>
    /// Queue that processed the LLM inference tasks in a structured concurrency manner.
    let queue: LLMInferenceQueue<String>

    #if canImport(Security)
    @Dependency(KeychainStorage.self) private var keychainStorage

    /// The credential store handed to each session.
    private var credentialStorage: LLMCredentialStorage? { keychainStorage }
    #else
    /// No Keychain on this platform; tokens come from the configuration instead.
    private var credentialStorage: LLMCredentialStorage? { nil }
    #endif
    @MainActor public var state: LLMPlatformState {
        self.queue.platformState
    }

    /// Creates an instance of the ``LLMOpenAIPlatform``.
    ///
    /// - Parameters:
    ///     - configuration: The configuration of the platform.
    public init(configuration: LLMOpenAILikePlatformConfiguration<PlatformDefinition>) {
        self.configuration = configuration
        self.queue = LLMInferenceQueue(
            maxConcurrentTasks: configuration.concurrentStreams,
            taskPriority: configuration.taskPriority
        )
    }


    public func run() async {
        do {
            // Run the LLM task queue
            try await self.queue.runQueue()
        } catch is CancellationError {
            // No-op, shutdown
        } catch {
            fatalError("Inconsistent state of the LLMOpenAIPlatform: \(error)")
        }
    }

    public func callAsFunction(with llmSchema: LLMOpenAILikeSchema<PlatformDefinition>) -> LLMOpenAILikeSession<PlatformDefinition> {
        LLMOpenAILikeSession<PlatformDefinition>(self, schema: llmSchema, keychainStorage: credentialStorage)
    }


    deinit {
        self.queue.shutdown()   // Safeguard shutdown of queue (should happen upon `ServiceModule/run() cancellation)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMOpenAILikePlatform {
    /// The platform's default credentials username for storing an API key to the keychain.
    static var credentialsUsername: String {
        "\(PlatformDefinition.platformName)_Token"
    }
    
    #if canImport(Security)
    /// Deletes the platform's API key credentials from the keychain.
    ///
    /// - Note: This function requires that the platform's configuration use a keychain-based auth token.
    ///     Otherwise, nothing will be done.
    public func clearApiKeyCredentials(in keychain: KeychainStorage) throws {
        switch configuration.authToken {
        case let .keychain(tag, username):
            try keychain.deleteCredentials(withUsername: username, for: tag)
        case .none, .constant, .closure:
            break
        }
    }
    #endif
}
