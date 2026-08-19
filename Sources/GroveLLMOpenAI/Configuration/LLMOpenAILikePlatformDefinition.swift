//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

public import Foundation
import GeneratedOpenAIClient
import OpenAPIRuntime


/// The API a model is served over.
@available(iOS 18, macOS 15, watchOS 11, *)
public enum LLMOpenAIAPIMode: String, Codable, Hashable, Sendable {
    /// The `/v1/chat/completions` API.
    case chatCompletions
    /// The `/v1/responses` API, which additionally supports server-side conversation state and reasoning summaries.
    case responses
}


/// How a platform picks the API a request is served over.
@available(iOS 18, macOS 15, watchOS 11, *)
public enum LLMOpenAIAPIModePolicy: Hashable, Sendable {
    /// Let each model decide, via ``LLMOpenAILikePlatformModelType/apiMode``.
    case perModel
    /// Serve every model over the given API, whatever the model itself declares.
    ///
    /// OpenAI-compatible gateways front several vendors through one endpoint, and rarely implement all of OpenAI's
    /// surface faithfully. Prefer `.fixed(.responses)` when the gateway supports the Responses API, including via
    /// ``LLMOpenAILikePlatformConfiguration/streamingFallback`` when only non-streaming responses work. Use
    /// `.fixed(.chatCompletions)` only when the gateway does not support `/v1/responses` at all.
    case fixed(LLMOpenAIAPIMode)


    /// The API the given model should be served over under this policy.
    public func resolve(for modelType: some LLMOpenAILikePlatformModelType) -> LLMOpenAIAPIMode {
        switch self {
        case .perModel: modelType.apiMode
        case .fixed(let mode): mode
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
public protocol LLMOpenAILikePlatformDefinition: Sendable {
    /// Defines the models available on this platform
    associatedtype ModelType: LLMOpenAILikePlatformModelType

    /// The name of the platform, e.g. "OpenAI", or "Anthropic"
    static var platformName: String { get }

    /// The platform's default server endpoint that inference tasks should be dispatched to.
    static var defaultServerUrl: URL { get }

    /// A URL-like identifier used as the service name when storing API keys for this platform to the keychain.
    ///
    /// This does not have to be a live URL; it just needs to uniquely identify the platform.
    /// For example, the identifier for the ``OpenAIPlatformDefinition`` is `api.openai.com`.
    static var platformServiceIdentifier: String { get }

    /// URL of the platform's developer console website.
    ///
    /// Used in the UI when displaying API key instructions.
    static var platformDeveloperConsoleUrl: URL? { get }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMOpenAILikePlatformDefinition {
    public static var platformDeveloperConsoleUrl: URL? { nil } // swiftlint:disable:this missing_docs
}


@available(iOS 18, macOS 15, watchOS 11, *)
public protocol LLMOpenAILikePlatformModelType: Hashable, RawRepresentable<String>, Codable, Identifiable, ExpressibleByStringLiteral, Sendable {
    /// The default model, that should be used as a fallback.
    static var `default`: Self { get }

    /// The list of well-known model types.
    ///
    /// Used e.g. when picking a model in the UI.
    static var wellKnownModels: [Self] { get }

    /// The API this model should be served over.
    ///
    /// Defaults to ``LLMOpenAIAPIMode/chatCompletions`` for backward compatibility. Platforms should override this
    /// with ``LLMOpenAIAPIMode/responses`` whenever the model and endpoint support it.
    var apiMode: LLMOpenAIAPIMode { get }

    /// Whether this model can emit reasoning summaries during inference.
    ///
    /// When `true`, `GroveLLMOpenAI` requests `reasoning.summary = .auto` for requests made via the Responses API,
    /// and propagates the resulting summaries into the `LLMContext`. Defaults to `false`.
    var supportsReasoningSummary: Bool { get }

    /// Creates a `ModelType` from a raw string value
    init(rawValue: String)
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMOpenAILikePlatformModelType {
    public var id: some Hashable { // swiftlint:disable:this missing_docs
        rawValue
    }

    public var apiMode: LLMOpenAIAPIMode { // swiftlint:disable:this missing_docs
        .chatCompletions
    }

    public var supportsReasoningSummary: Bool { // swiftlint:disable:this missing_docs
        false
    }

    public init(stringLiteral value: String) { // swiftlint:disable:this missing_docs
        self.init(rawValue: value)
    }
}
