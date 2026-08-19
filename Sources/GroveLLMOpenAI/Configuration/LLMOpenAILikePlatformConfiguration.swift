//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import GeneratedOpenAIClient
public import GroveKeychainStorage
public import OpenAPIRuntime


/// Represents the configuration of an OpenAI-like `LLMPlatform`.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct LLMOpenAILikePlatformConfiguration<PlatformDefinition: LLMOpenAILikePlatformDefinition> {
    /// The platform's model type.
    public typealias ModelType = PlatformDefinition.ModelType

    /// The server endpoint that the inference tasks are dispatched to.
    public let serverUrl: URL
    /// The OpenAI API token on a global basis.
    public let authToken: RemoteLLMInferenceAuthToken
    /// Indicates the maximum number of concurrent streams to the OpenAI API.
    public let concurrentStreams: Int
    /// Maximum network timeout of OpenAI requests in seconds.
    public let timeout: TimeInterval
    /// The retry policy that should be used.
    public let retryPolicy: RetryPolicy
    /// The task priority of the initiated LLM inference tasks.
    public let taskPriority: TaskPriority
    /// Additional middlewares that should be used by the client.
    ///
    /// The `ClientMiddleware` instances specified here are placed after any other middleware configured by GroveLLM (e.g., the retry mechanism).
    public let middlewares: [any ClientMiddleware]

    
    /// Creates the ``LLMOpenAIPlatformConfiguration`` which configures the Grove ``LLMOpenAIPlatform``.
    ///
    /// - Parameters:
    ///   - serverUrl: The server `URL` that the inference tasks are dispatched to. Defaults to the OpenAI API endpoint specified in the OpenAI OpenAPI document.
    ///   - authToken: Specifies the OpenAI API token on a global basis.
    ///   - concurrentStreams: Indicates the maximum number of concurrent streams to the OpenAI API, defaults to `10`.
    ///   - timeout: Indicates the maximum network timeout of OpenAI requests in seconds. defaults to `60`.
    ///   - retryPolicy: The retry policy that should be used, defaults to `3` retry attempts.
    ///   - taskPriority: The task priority of the initiated LLM inference tasks, defaults to `.userInitiated`.
    ///   - middlewares: Additional middlewares that should be used for requests.
    public init(
        serverUrl: URL = PlatformDefinition.defaultServerUrl,
        authToken: RemoteLLMInferenceAuthToken,
        concurrentStreams: Int = 10,
        timeout: TimeInterval = 60,
        retryPolicy: RetryPolicy = .attempts(3),
        taskPriority: TaskPriority = .userInitiated,
        middlewares: [any ClientMiddleware] = []
    ) {
        self.serverUrl = serverUrl
        self.authToken = authToken
        self.concurrentStreams = concurrentStreams
        self.timeout = timeout
        self.retryPolicy = retryPolicy
        self.taskPriority = taskPriority
        self.middlewares = middlewares
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension CredentialsTag {
    /// Constructs the canonical tag for storing the specified platform's API keys in the keychain.
    public static func `for`(_ platformDef: (some LLMOpenAILikePlatformDefinition).Type) -> Self {
        .genericPassword(forService: platformDef.platformServiceIdentifier)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension RemoteLLMInferenceAuthToken {
    /// Configures an auth token that uses the platform's default username and service identifier.
    public static func keychain<D>(for platform: LLMOpenAILikePlatform<D>.Type) -> Self {
        .keychain(
            tag: .for(D.self),
            username: platform.credentialsUsername
        )
    }
}
