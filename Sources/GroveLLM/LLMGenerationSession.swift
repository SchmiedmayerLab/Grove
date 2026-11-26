//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// The outcome of one provider request or of a whole generation.
public enum LLMGenerationStatus: Sendable, Hashable {
    /// The provider reported a finished answer.
    case completed
    /// The provider reported a truncated answer, for example at the output limit.
    case incomplete
    /// The request or generation failed, including a stream that ended without the provider's terminal marker.
    case failed
    /// The caller or the session cancelled the request or generation, or the provider reported the response as
    /// cancelled.
    case cancelled
}

/// The reason a provider gave for ending a request.
///
/// Only recognized provider finish reasons are surfaced; any other reason is ``LLMFinishReason/other``.
public enum LLMFinishReason: Sendable, Hashable {
    /// The model finished its answer.
    case stop
    /// The model requested tool calls; the generation continues with another request.
    case toolCalls
    /// The answer reached the output token limit.
    case outputLimit
    /// The provider filtered the answer.
    case contentFilter
    /// The response stream ended without the provider's terminal marker.
    case interrupted
    /// The provider reported a reason this library does not recognize.
    case other
}

/// Token counts a provider reported.
///
/// Each count is optional. A reported zero is a measurement; `nil` means the provider supplied no measurement.
/// The counts exclude hosted tool fees and are not a cost receipt.
public struct LLMTokenUsage: Sendable, Hashable {
    /// The input tokens the provider counted, if reported.
    public var inputTokens: Int?
    /// The output tokens the provider counted, if reported.
    public var outputTokens: Int?

    /// Creates token usage from reported counts.
    public init(inputTokens: Int? = nil, outputTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

/// The outcome of one transport attempt of a provider request.
///
/// Request and attempt numbers start at one within each generation. Retries of the same request share a request
/// number and increase the attempt number. An unstreamed fallback and each tool round start a new request.
/// Provider identifiers can correlate a result with provider records; they do not guarantee that a request was
/// processed exactly once. A result contains no credentials, prompts or model output.
public struct LLMRequestResult: Sendable, Hashable {
    /// The request number within the generation.
    public let request: Int
    /// The attempt number within the request.
    public let attempt: Int
    /// The outcome of this attempt.
    public var status: LLMGenerationStatus
    /// The reason the provider gave for ending the response, if any.
    public var reason: LLMFinishReason?
    /// The provider's identifier for the response, if reported.
    public var providerID: String?
    /// The model the provider reported, if any.
    public var model: String?
    /// The token usage the provider reported for this attempt.
    ///
    /// A failure before a response arrived has unknown usage.
    public var usage: LLMTokenUsage

    /// Creates a request result without a reason, provider identity or usage.
    public init(request: Int, attempt: Int, status: LLMGenerationStatus) {
        self.request = request
        self.attempt = attempt
        self.status = status
        self.usage = .init()
    }
}

/// The outcome of a whole generation.
public struct LLMGenerationResult: Sendable, Hashable {
    /// The outcome of the generation.
    ///
    /// A generation completes only when its last request completed without pending tool calls.
    public let status: LLMGenerationStatus
    /// The number of transport attempts the generation made.
    public let attempts: Int
    /// The total token usage of all attempts.
    ///
    /// A count is unknown if any attempt did not report it.
    public let usage: LLMTokenUsage

    /// Creates a generation result.
    public init(status: LLMGenerationStatus, attempts: Int, usage: LLMTokenUsage) {
        self.status = status
        self.attempts = attempts
        self.usage = usage
    }
}

/// An element of a generation's event stream.
public enum LLMGenerationEvent: Sendable, Hashable {
    /// A piece of the answer text.
    case textDelta(String)
    /// The outcome of one transport attempt.
    case requestFinished(LLMRequestResult)
    /// The outcome of the generation. It is the last event and follows the tool loop.
    case finished(LLMGenerationResult)
}

/// Errors that end a generation event stream.
public enum LLMGenerationStreamError: Error, Equatable {
    /// The consumer fell behind and the stream's buffer filled up. The generation stopped.
    case bufferOverflow
}

/// A session that reports the outcome of each provider request and of the generation.
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol LLMGenerationSession: LLMSession {
    /// Starts one generation and returns its events.
    ///
    /// Consume the returned stream with a single iterator. ``LLMSession/generate()`` runs the same generation and
    /// returns only its text.
    func generateEvents() async throws -> AsyncThrowingStream<LLMGenerationEvent, any Error>
}
