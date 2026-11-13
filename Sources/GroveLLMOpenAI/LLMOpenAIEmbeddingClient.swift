//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
public import GeneratedOpenAIClient
public import GroveLLM
public import OpenAPIRuntime
import OSLog


/// OpenAI-compatible embeddings client that does not require a chat session or Spezi `LLMRunner`.
///
/// Uses the generated `createEmbedding` operation with bearer authentication and optional retries.
/// Retries default to ``RetryPolicy/never``. Configuring retries may submit additional charged work;
/// cancellation is never retried by that policy.
///
/// Chunking, vector storage, retrieval ranking, and authorization remain application responsibilities.
///
/// ### Usage
///
/// ```swift
/// import GroveLLM
/// import GroveLLMOpenAI
///
/// let client = LLMOpenAIEmbeddingClient(
///     serverURL: OpenAIPlatformDefinition.defaultServerUrl,
///     authToken: .constant("sk-...")
/// )
/// let result = try await client.embed(
///     ["hello", "world"],
///     model: "text-embedding-3-small",
///     dimensions: nil
/// )
/// // result.vectors[0] belongs to "hello"
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
public struct LLMOpenAIEmbeddingClient: LLMEmbeddingProvider {
    private static let logger = Logger(subsystem: "org.grovealliance", category: "GroveLLMOpenAI.Embeddings")

    /// Default maximum number of texts per request (OpenAI array upper bound).
    public static let defaultMaxBatchCount = 2048
    /// Default UTF-8 byte bound per input after JSON string escaping.
    public static let defaultMaxInputBytes = 256_000
    /// Default UTF-8 byte bound for the complete encoded JSON request body.
    public static let defaultMaxRequestBytes = 8_000_000
    /// Default byte bound for the HTTP response body before decoding.
    public static let defaultMaxResponseBytes = 64_000_000
    /// Default request timeout for the URL session transport.
    public static let defaultTimeout: TimeInterval = 60

    private let client: Client
    private let requestIDBox: EmbeddingRequestIDBox
    private let maxBatchCount: Int
    private let maxInputBytes: Int
    private let maxRequestBytes: Int
    private let handleErrorCode: @Sendable (Int) -> LLMOpenAIError


    /// Creates an embeddings client.
    ///
    /// - Parameters:
    ///   - serverURL: OpenAI-compatible API base URL.
    ///   - authToken: Token source evaluated on every request. Prefer `.constant` or `.closure` on Linux;
    ///     `.keychain` requires `keychainStorage`.
    ///   - retryPolicy: Retry policy. Defaults to ``RetryPolicy/never``. `.attempts` must be at least `1`.
    ///     Explicit retries can submit additional charged work; cancellation is not retried.
    ///   - maxBatchCount: Maximum texts per request. Must be positive.
    ///   - maxInputBytes: Maximum UTF-8 bytes per input after JSON escaping. Must be positive.
    ///   - maxRequestBytes: Maximum UTF-8 bytes of the encoded JSON request body. Must be positive.
    ///   - maxResponseBytes: Maximum HTTP response body size. Must be positive.
    ///   - timeout: URL session request timeout when using the default transport.
    ///   - transport: Injectable OpenAPI transport for tests. Defaults to an ephemeral `URLSession`.
    ///   - middlewares: Extra middlewares appended after auth, retry, response-size, and request-id capture.
    ///
    /// Prefer ``RemoteLLMInferenceAuthToken/constant(_:)`` or ``RemoteLLMInferenceAuthToken/closure(_:)`` for the
    /// auth token. Keychain-backed tokens require the Spezi chat session path and are not accepted here.
    public init(
        serverURL: URL,
        authToken: RemoteLLMInferenceAuthToken,
        retryPolicy: RetryPolicy = .never,
        maxBatchCount: Int = Self.defaultMaxBatchCount,
        maxInputBytes: Int = Self.defaultMaxInputBytes,
        maxRequestBytes: Int = Self.defaultMaxRequestBytes,
        maxResponseBytes: Int = Self.defaultMaxResponseBytes,
        timeout: TimeInterval = Self.defaultTimeout,
        transport: (any ClientTransport)? = nil,
        middlewares: [any ClientMiddleware] = []
    ) throws {
        try Self.validateConfiguration(
            retryPolicy: retryPolicy,
            maxBatchCount: maxBatchCount,
            maxInputBytes: maxInputBytes,
            maxRequestBytes: maxRequestBytes,
            maxResponseBytes: maxResponseBytes
        )

        let requestIDBox = EmbeddingRequestIDBox()
        self.requestIDBox = requestIDBox
        self.maxBatchCount = maxBatchCount
        self.maxInputBytes = maxInputBytes
        self.maxRequestBytes = maxRequestBytes
        self.handleErrorCode = { status in
            // Mirror chat session mapping without requiring an `LLMOpenAILikeSession` instance.
            switch status {
            case 400: .invalidRequest
            case 401, 403: .invalidAPIToken
            case 429: .insufficientQuota
            case 500, 503: .generationError
            default: .generationError
            }
        }

        #if canImport(Security)
        if case .keychain = authToken {
            throw LLMOpenAIEmbeddingError.unsupportedKeychainAuth
        }
        #endif

        self.client = OpenAICompatibleClientFactory.makeClient(
            serverURL: serverURL,
            authToken: authToken,
            keychainStorage: nil,
            retryPolicy: retryPolicy,
            timeout: timeout,
            transport: transport,
            middlewares: [
                ResponseByteLimitMiddleware(maxResponseBytes: maxResponseBytes),
                EmbeddingRequestIDMiddleware(box: requestIDBox)
            ] + middlewares
        )
    }


    /// Embeds a text batch.
    ///
    /// - Parameters:
    ///   - texts: Non-empty UTF-8 texts. Empty batches and empty strings fail before dispatch.
    ///   - model: Provider model identifier.
    ///   - dimensions: Optional positive requested dimensionality.
    /// - Returns: Ordered vectors aligned with `texts`.
    public func embed(
        _ texts: [String],
        model: String,
        dimensions: Int? = nil
    ) async throws -> LLMEmbeddingResult {
        try validateInputs(texts, dimensions: dimensions)

        let request = Components.Schemas.CreateEmbeddingRequest(
            input: .case2(texts),
            model: .init(value1: model),
            encoding_format: .float,
            dimensions: dimensions,
            user: nil
        )
        try validateEncodedRequestSize(request)

        requestIDBox.value = nil

        let output: Operations.createEmbedding.Output
        do {
            output = try await client.createEmbedding(
                body: .json(request)
            )
        } catch let error as CancellationError {
            throw error
        } catch let error as LLMOpenAIEmbeddingError {
            throw error
        } catch let error as ClientError {
            if let embeddingError = error.underlyingError as? LLMOpenAIEmbeddingError {
                throw embeddingError
            }
            Self.logger.error("GroveLLMOpenAI embeddings connectivity failure: \(error)")
            throw LLMOpenAIEmbeddingError.connectivity(error)
        } catch {
            throw LLMOpenAIEmbeddingError.connectivity(error)
        }

        switch output {
        case .ok(let ok):
            let payload = try ok.body.json
            return try mapResponse(payload, expectedCount: texts.count, requestedDimensions: dimensions)
        case .undocumented(let statusCode, _):
            throw LLMOpenAIEmbeddingError.provider(handleErrorCode(statusCode))
        }
    }


    // MARK: - Validation

    private static func validateConfiguration(
        retryPolicy: RetryPolicy,
        maxBatchCount: Int,
        maxInputBytes: Int,
        maxRequestBytes: Int,
        maxResponseBytes: Int
    ) throws {
        if case .attempts(let count) = retryPolicy, count < 1 {
            throw LLMOpenAIEmbeddingError.invalidRetryPolicy
        }
        guard maxBatchCount > 0, maxInputBytes > 0, maxRequestBytes > 0, maxResponseBytes > 0 else {
            throw LLMOpenAIEmbeddingError.invalidLimit
        }
    }

    private func validateInputs(_ texts: [String], dimensions: Int?) throws {
        guard !texts.isEmpty else {
            throw LLMOpenAIEmbeddingError.emptyBatch
        }
        guard texts.count <= maxBatchCount else {
            throw LLMOpenAIEmbeddingError.requestTooLarge
        }
        if let dimensions, dimensions < 1 {
            throw LLMOpenAIEmbeddingError.invalidDimensions
        }
        for text in texts {
            guard !text.isEmpty else {
                throw LLMOpenAIEmbeddingError.emptyInput
            }
            let escapedBytes = try jsonEscapedUTF8ByteCount(text)
            guard escapedBytes <= maxInputBytes else {
                throw LLMOpenAIEmbeddingError.inputTooLarge
            }
        }
    }

    private func validateEncodedRequestSize(_ request: Components.Schemas.CreateEmbeddingRequest) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        guard data.count <= maxRequestBytes else {
            throw LLMOpenAIEmbeddingError.requestTooLarge
        }
    }

    /// Counts UTF-8 bytes of a JSON string literal contents after escaping (excluding surrounding quotes).
    private func jsonEscapedUTF8ByteCount(_ text: String) throws -> Int {
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(text)
        // JSONEncoder wraps strings in quotes; subtract the two quote bytes.
        guard encoded.count >= 2 else {
            return encoded.count
        }
        return encoded.count - 2
    }


    // MARK: - Response mapping

    private func mapResponse(
        _ response: Components.Schemas.CreateEmbeddingResponse,
        expectedCount: Int,
        requestedDimensions: Int?
    ) throws -> LLMEmbeddingResult {
        let usage = try mapUsage(response.usage)
        var slots: [[Float]?] = Array(repeating: nil, count: expectedCount)

        for item in response.data {
            guard item.index >= 0, item.index < expectedCount else {
                throw LLMOpenAIEmbeddingError.malformedResponse
            }
            guard slots[item.index] == nil else {
                throw LLMOpenAIEmbeddingError.malformedResponse
            }
            let vector = item.embedding
            guard !vector.isEmpty, vector.allSatisfy({ $0.isFinite }) else {
                throw LLMOpenAIEmbeddingError.malformedResponse
            }
            slots[item.index] = vector
        }

        guard slots.allSatisfy({ $0 != nil }) else {
            throw LLMOpenAIEmbeddingError.malformedResponse
        }
        let vectors = slots.map { $0! }
        let dimensions = vectors[0].count
        guard dimensions > 0 else {
            throw LLMOpenAIEmbeddingError.malformedResponse
        }
        if let requestedDimensions, dimensions != requestedDimensions {
            throw LLMOpenAIEmbeddingError.malformedResponse
        }
        guard vectors.allSatisfy({ $0.count == dimensions }) else {
            throw LLMOpenAIEmbeddingError.malformedResponse
        }

        return LLMEmbeddingResult(
            model: response.model,
            vectors: vectors,
            dimensions: dimensions,
            usage: usage,
            providerRequestID: requestIDBox.value
        )
    }

    private func mapUsage(
        _ usage: Components.Schemas.CreateEmbeddingResponse.usagePayload
    ) throws -> LLMEmbeddingUsage {
        guard usage.prompt_tokens >= 0, usage.total_tokens >= 0 else {
            throw LLMOpenAIEmbeddingError.malformedResponse
        }
        guard usage.total_tokens >= usage.prompt_tokens else {
            throw LLMOpenAIEmbeddingError.malformedResponse
        }
        return LLMEmbeddingUsage(
            inputTokens: usage.prompt_tokens,
            totalTokens: usage.total_tokens
        )
    }
}
