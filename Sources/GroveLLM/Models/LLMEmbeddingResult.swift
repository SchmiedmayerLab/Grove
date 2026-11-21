//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Token usage reported for an embedding request.
///
/// Providers that do not report usage leave ``LLMEmbeddingResult/usage`` as `nil`. OpenAI-compatible
/// responses that omit the required usage object fail decoding instead of synthesizing zeros.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct LLMEmbeddingUsage: Sendable, Hashable {
    /// Number of tokens consumed by the input texts.
    public let inputTokens: Int
    /// Total tokens billed for the request.
    public let totalTokens: Int


    /// Creates usage totals reported by an embedding provider.
    ///
    /// - Parameters:
    ///   - inputTokens: Tokens attributed to the input texts.
    ///   - totalTokens: Total tokens for the request.
    public init(inputTokens: Int, totalTokens: Int) {
        self.inputTokens = inputTokens
        self.totalTokens = totalTokens
    }
}


/// Ordered embedding vectors returned for a text batch.
///
/// ``vectors`` is indexed identically to the input texts: `vectors[i]` belongs to `texts[i]`.
/// ``model`` is the identifier returned by the provider, not an application-invented version string.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct LLMEmbeddingResult: Sendable, Hashable {
    /// Provider model identifier from the embedding response.
    public let model: String
    /// Embedding vectors in input order.
    public let vectors: [[Float]]
    /// Dimensionality shared by every vector in ``vectors``.
    public let dimensions: Int
    /// Optional usage totals when the provider reports them.
    public let usage: LLMEmbeddingUsage?
    /// Provider request identifier when the transport exposes one; otherwise `nil`.
    public let providerRequestID: String?


    /// Creates an embedding result.
    ///
    /// - Parameters:
    ///   - model: Provider model identifier.
    ///   - vectors: Embedding vectors aligned with the input texts.
    ///   - dimensions: Shared vector length.
    ///   - usage: Optional token usage.
    ///   - providerRequestID: Optional HTTP / provider request identifier.
    public init(
        model: String,
        vectors: [[Float]],
        dimensions: Int,
        usage: LLMEmbeddingUsage? = nil,
        providerRequestID: String? = nil
    ) {
        self.model = model
        self.vectors = vectors
        self.dimensions = dimensions
        self.usage = usage
        self.providerRequestID = providerRequestID
    }
}
