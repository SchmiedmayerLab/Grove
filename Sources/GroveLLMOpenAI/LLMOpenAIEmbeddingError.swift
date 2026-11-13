//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
public import GroveLLM


/// Errors raised while validating or executing OpenAI-compatible embedding requests.
@available(iOS 18, macOS 15, watchOS 11, *)
public enum LLMOpenAIEmbeddingError: LLMError {
    /// The text batch was empty.
    case emptyBatch
    /// At least one input string was empty.
    case emptyInput
    /// Requested dimensions were missing or not strictly positive.
    case invalidDimensions
    /// A configured byte or batch bound was missing or not strictly positive.
    case invalidLimit
    /// The retry policy requested fewer than one attempt.
    case invalidRetryPolicy
    /// Keychain-backed auth tokens are not supported by the standalone embedding client.
    case unsupportedKeychainAuth
    /// An input exceeded the per-input UTF-8 byte bound (after JSON-string escaping).
    case inputTooLarge
    /// The encoded request exceeded the total request byte bound.
    case requestTooLarge
    /// The HTTP response body exceeded the response byte bound.
    case responseTooLarge
    /// The provider returned a malformed embedding payload.
    case malformedResponse
    /// Mapped OpenAI HTTP failure.
    case provider(LLMOpenAIError)
    /// Transport-level failure before a documented HTTP status was available.
    case connectivity(any Error)


    public var isRetriable: Bool {
        switch self {
        case .provider(let error):
            error.isRetriable
        case .connectivity:
            true
        case .emptyBatch, .emptyInput, .invalidDimensions, .invalidLimit, .invalidRetryPolicy,
             .unsupportedKeychainAuth, .inputTooLarge, .requestTooLarge, .responseTooLarge, .malformedResponse:
            false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .emptyBatch:
            "The embedding batch contained no texts."
        case .emptyInput:
            "The embedding batch contained an empty string."
        case .invalidDimensions:
            "Requested embedding dimensions must be a positive integer."
        case .invalidLimit:
            "Embedding size limits must be positive integers."
        case .invalidRetryPolicy:
            "Embedding retry policies must request at least one attempt, or never retry."
        case .unsupportedKeychainAuth:
            "Keychain-backed auth tokens are not supported by LLMOpenAIEmbeddingClient."
        case .inputTooLarge:
            "An embedding input exceeded the configured per-input byte limit."
        case .requestTooLarge:
            "The encoded embedding request exceeded the configured request byte limit."
        case .responseTooLarge:
            "The embedding response exceeded the configured response byte limit."
        case .malformedResponse:
            "The embedding provider returned a malformed response."
        case .provider(let error):
            error.errorDescription
        case .connectivity(let error):
            error.localizedDescription
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .emptyBatch, .emptyInput:
            "Provide a non-empty batch of non-empty UTF-8 strings."
        case .invalidDimensions:
            "Pass a positive dimensions value, or omit dimensions to use the model default."
        case .invalidLimit, .invalidRetryPolicy:
            "Reconfigure the embedding client with positive bounds and a valid retry policy."
        case .unsupportedKeychainAuth:
            "Pass a constant or closure-based RemoteLLMInferenceAuthToken instead."
        case .inputTooLarge, .requestTooLarge:
            "Reduce batch size or input length, or raise the configured byte bounds."
        case .responseTooLarge:
            "Request fewer embeddings or raise the configured response byte bound."
        case .malformedResponse:
            "Retry against a compatible embeddings endpoint, or inspect the provider response."
        case .provider(let error):
            error.recoverySuggestion
        case .connectivity:
            "Check network connectivity to the embeddings endpoint."
        }
    }

    public var failureReason: String? {
        switch self {
        case .emptyBatch, .emptyInput, .invalidDimensions, .invalidLimit, .invalidRetryPolicy,
             .unsupportedKeychainAuth, .inputTooLarge, .requestTooLarge:
            "The embedding request was rejected before it was sent."
        case .responseTooLarge, .malformedResponse:
            "The embedding response failed local validation."
        case .provider(let error):
            error.failureReason
        case .connectivity:
            "The embedding request did not complete successfully."
        }
    }


    public static func == (lhs: LLMOpenAIEmbeddingError, rhs: LLMOpenAIEmbeddingError) -> Bool {
        switch (lhs, rhs) {
        case (.emptyBatch, .emptyBatch),
             (.emptyInput, .emptyInput),
             (.invalidDimensions, .invalidDimensions),
             (.invalidLimit, .invalidLimit),
             (.invalidRetryPolicy, .invalidRetryPolicy),
             (.unsupportedKeychainAuth, .unsupportedKeychainAuth),
             (.inputTooLarge, .inputTooLarge),
             (.requestTooLarge, .requestTooLarge),
             (.responseTooLarge, .responseTooLarge),
             (.malformedResponse, .malformedResponse):
            true
        case (.provider(let lhsError), .provider(let rhsError)):
            lhsError == rhsError
        case (.connectivity, .connectivity):
            true
        default:
            false
        }
    }
}
