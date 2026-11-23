//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Produces embedding vectors for text batches without requiring a chat session.
///
/// Chunking, vector storage, retrieval ranking, and authorization policy remain application
/// responsibilities. Implementations must keep ``LLMEmbeddingResult/vectors`` aligned with the
/// input order of `texts`.
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol LLMEmbeddingProvider: Sendable {
    /// Embeds a batch of UTF-8 texts.
    ///
    /// - Parameters:
    ///   - texts: Non-empty texts to embed. Empty batches and empty strings are rejected by
    ///     conforming clients before dispatch.
    ///   - model: Provider model identifier.
    ///   - dimensions: Optional requested output dimensionality for providers that support it.
    /// - Returns: Ordered embedding vectors and optional usage metadata.
    func embed(
        _ texts: [String],
        model: String,
        dimensions: Int?
    ) async throws -> LLMEmbeddingResult
}
