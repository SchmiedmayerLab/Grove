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


/// The OpenAI platform's definition.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct OpenAIPlatformDefinition: LLMOpenAILikePlatformDefinition {
    public struct ModelType: LLMOpenAILikePlatformModelType {
        /// The identifier of the underlying model.
        public let rawValue: String
        /// Creates a new `ModelType`
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
        /// Creates a new `ModelType`
        public init(stringLiteral rawValue: String) {
            self.rawValue = rawValue
        }
    }
    
    public static let platformName = "OpenAI"
    public static let platformServiceIdentifier = "api.openai.com"
    
    public static let platformDeveloperConsoleUrl = URL(string: "https://platform.openai.com/account/api-keys")
    
    public static let defaultServerUrl: URL = {
        guard let url = try? Servers.Server1.url() else {
            fatalError("The default OpenAI API endpoint couldn't be extracted from the OpenAI OpenAPI document.")
        }
        return url
    }()
}


// MARK: Type Specializations

/// Represents the configuration of the Grove ``LLMOpenAIPlatform``.
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias LLMOpenAIPlatformConfiguration = LLMOpenAILikePlatformConfiguration<OpenAIPlatformDefinition>


/// Represents the parameters of an OpenAI LLM model.
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias LLMOpenAIParameters = LLMOpenAILikeParameters<OpenAIPlatformDefinition>


/// LLM execution platform of an ``LLMOpenAISchema``.
///
/// The ``LLMOpenAIPlatform`` turns a received ``LLMOpenAISchema`` to an executable ``LLMOpenAISession``.
/// Use ``LLMOpenAILikePlatform/callAsFunction(with:)`` with an ``LLMOpenAISchema`` parameter to get an executable ``LLMOpenAISession`` that does the actual inference.
///
/// The platform can be configured with the ``LLMOpenAIPlatformConfiguration``, enabling developers to specify properties like a custom server `URL`s, API tokens, the retry policy or timeouts.
///
/// - Important: ``LLMOpenAIPlatform`` shouldn't be used directly but used via the `GroveLLM` `LLMRunner` that delegates the requests towards the ``LLMOpenAIPlatform``.
/// The `GroveLLM` `LLMRunner` must be configured with the ``LLMOpenAIPlatform`` within the Grove `Configuration`.
///
/// - Tip: For more information, refer to the documentation of the `LLMPlatform` from GroveLLM.
///
/// ### Usage
///
/// The example below demonstrates the setup of the ``LLMOpenAIPlatform`` within the Grove `Configuration`.
///
/// ```swift
/// class TestAppDelegate: GroveAppDelegate {
///     override var configuration: Configuration {
///         Configuration {
///             LLMRunner {
///                 LLMOpenAIPlatform()
///             }
///         }
///     }
/// }
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias LLMOpenAIPlatform = LLMOpenAILikePlatform<OpenAIPlatformDefinition>


/// Defines the type and configuration of the ``LLMOpenAISession``.
///
/// The ``LLMOpenAISchema`` is used as a configuration for the to-be-used OpenAI LLM. It contains all information necessary for the creation of an executable ``LLMOpenAISession``.
/// It is bound to a ``LLMOpenAIPlatform`` that is responsible for turning the ``LLMOpenAISchema`` to an ``LLMOpenAISession``.
///
/// - Tip: ``LLMOpenAISchema`` also enables the function calling mechanism to establish a structured, bidirectional, and reliable communication between the OpenAI LLMs and external tools. For details, refer to ``LLMTool`` and ``LLMTool/Parameter`` or the <doc:ToolCalling> DocC article.
///
/// - Tip: For more information, refer to the documentation of the `LLMSchema` from GroveLLM.
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias LLMOpenAISchema = LLMOpenAILikeSchema<OpenAIPlatformDefinition>


/// Represents an ``LLMOpenAISchema`` in execution.
///
/// The ``LLMOpenAISession`` is the executable version of the OpenAI LLM containing context and state as defined by the ``LLMOpenAISchema``.
/// It provides access to text-based models from OpenAI, such as GPT-3.5 or GPT-4.
///
/// The inference is started by ``LLMOpenAILikeSession/generate()``, returning an `AsyncThrowingStream` and can be cancelled via ``LLMOpenAILikeSession/cancel()``.
/// The ``LLMOpenAISession`` exposes its current state via the ``LLMOpenAILikeSession/context`` property, containing all the conversational history with the LLM.
///
/// - Warning: The ``LLMOpenAISession`` shouldn't be created manually but always through the ``LLMOpenAIPlatform`` via the `LLMRunner`.
///
/// - Tip: ``LLMOpenAISession`` also enables the function calling mechanism to establish a structured, bidirectional, and reliable communication between the OpenAI LLMs and external tools. For details, refer to ``LLMTool`` and ``LLMTool/Parameter`` or the <doc:ToolCalling> DocC article.
///
/// - Tip: For more information, refer to the documentation of the `LLMSession` from GroveLLM.
///
/// ### Usage
///
/// The example below demonstrates a minimal usage of the ``LLMOpenAISession`` via the `LLMRunner`.
///
/// ```swift
/// import GroveLLM
/// import GroveLLMOpenAI
/// import SwiftUI
///
/// struct LLMOpenAIDemoView: View {
///     @Environment(LLMRunner.self) var runner
///     @State var responseText = ""
///
///     var body: some View {
///         Text(responseText)
///             .task {
///                 // Instantiate the `LLMOpenAISchema` to an `LLMOpenAISession` via the `LLMRunner`.
///                 let llmSession: LLMOpenAISession = runner(
///                     with: LLMOpenAISchema(
///                         parameters: .init(
///                             modelType: .gpt4o,
///                             systemPrompt: "You're a helpful assistant that answers questions from users.",
///                             overwritingAuthToken: "abc123"
///                         )
///                     )
///                 )
///
///                 do {
///                     for try await token in try await llmSession.generate() {
///                         responseText.append(token)
///                     }
///                 } catch {
///                     // Handle errors here. E.g., you can use `ViewState` and `viewStateAlert` from GroveViews.
///                 }
///             }
///     }
/// }
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias LLMOpenAISession = LLMOpenAILikeSession<OpenAIPlatformDefinition>


#if canImport(SwiftUI)
/// View to display an onboarding step for the user to enter an OpenAI API Key.
///
/// - Warning: Ensure that the ``LLMOpenAIPlatform`` is specified within the Grove `Configuration` when using this view in the onboarding flow.
///
/// - Important: Only use this if the corresponding LLM platform's config's auth token is set to `RemoteLLMInferenceAuthToken/keychain(_:CredentialsTag)`
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias LLMOpenAIAPITokenOnboardingStep = LLMOpenAILikeAPITokenOnboardingStep<OpenAIPlatformDefinition>


/// View to display an onboarding step for the user to select an OpenAI model.
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias LLMOpenAIModelOnboardingStep = LLMOpenAILikeModelOnboardingStep<OpenAIPlatformDefinition>
#endif


#if canImport(Security)
public import GroveKeychainStorage


@available(iOS 18, macOS 15, watchOS 11, *)
extension CredentialsTag {
    /// The canonical credentials tag for the OpenAI API key
    public static let openAIKey = Self.for(OpenAIPlatformDefinition.self)
}
#endif


// MARK: Models

// swiftlint:disable identifier_name missing_docs
@available(iOS 18, macOS 15, watchOS 11, *)
extension OpenAIPlatformDefinition.ModelType {
    public static let `default`: Self = .gpt5_6

    public static let wellKnownModels: [Self] = [
        .gpt5_6, .gpt5_6_sol, .gpt5_6_terra, .gpt5_6_luna,
        .gpt5_5, .gpt5_5_pro,
        .gpt5_4, .gpt5_4_pro, .gpt5_4_mini, .gpt5_4_nano,
        .gpt5_2, .gpt5_2_pro, .gpt5_1,
        .gpt5, .gpt5_mini, .gpt5_nano, .gpt5_chat, .gpt5_pro,
        .gpt4o, .gpt4o_mini,
        .gpt4_turbo,
        .gpt4_1, .gpt4_1_mini, .gpt4_1_nano,
        .o4_mini,
        .o3, .o3_pro, .o3_mini, .o3_mini_high,
        .o1_pro, .o1, .o1_mini,
        .gpt3_5_turbo
    ]

    /// The models that OpenAI only serves over the legacy Chat Completions API.
    ///
    /// Everything else — including model identifiers we don't know about — goes through the Responses API.
    private static let chatCompletionModelIds: Set<String> = [
        "gpt-4o", "gpt-4o-mini",
        "gpt-4-turbo",
        "gpt-3.5-turbo"
    ]

    // GPT-5 series
    public static let gpt5 = Self(rawValue: "gpt-5")
    public static let gpt5_mini = Self(rawValue: "gpt-5-mini")
    public static let gpt5_nano = Self(rawValue: "gpt-5-nano")
    public static let gpt5_chat = Self(rawValue: "gpt-5-chat-latest")
    public static let gpt5_pro = Self(rawValue: "gpt-5-pro")
    public static let gpt5_1 = Self(rawValue: "gpt-5.1")
    public static let gpt5_2 = Self(rawValue: "gpt-5.2")
    public static let gpt5_2_pro = Self(rawValue: "gpt-5.2-pro")
    public static let gpt5_4 = Self(rawValue: "gpt-5.4")
    public static let gpt5_4_pro = Self(rawValue: "gpt-5.4-pro")
    public static let gpt5_4_mini = Self(rawValue: "gpt-5.4-mini")
    public static let gpt5_4_nano = Self(rawValue: "gpt-5.4-nano")
    public static let gpt5_5 = Self(rawValue: "gpt-5.5")
    public static let gpt5_5_pro = Self(rawValue: "gpt-5.5-pro")

    /// Routes to whichever model OpenAI currently considers the flagship of the 5.6 family.
    public static let gpt5_6 = Self(rawValue: "gpt-5.6")
    /// The frontier model of the 5.6 family.
    public static let gpt5_6_sol = Self(rawValue: "gpt-5.6-sol")
    /// The 5.6 model balancing capability against cost.
    public static let gpt5_6_terra = Self(rawValue: "gpt-5.6-terra")
    /// The 5.6 model for cost-sensitive, high-volume work.
    public static let gpt5_6_luna = Self(rawValue: "gpt-5.6-luna")

    // GPT-4 series
    public static let gpt4o = Self(rawValue: "gpt-4o")
    public static let gpt4o_mini = Self(rawValue: "gpt-4o-mini")
    public static let gpt4_turbo = Self(rawValue: "gpt-4-turbo")
    public static let gpt4_1 = Self(rawValue: "gpt-4.1")
    public static let gpt4_1_mini = Self(rawValue: "gpt-4.1-mini")
    public static let gpt4_1_nano = Self(rawValue: "gpt-4.1-nano")

    // o-series
    public static let o4_mini = Self(rawValue: "o4-mini")
    public static let o3 = Self(rawValue: "o3")
    public static let o3_pro = Self(rawValue: "o3-pro")
    public static let o3_mini = Self(rawValue: "o3-mini")
    public static let o3_mini_high = Self(rawValue: "o3-mini-high")
    public static let o1_pro = Self(rawValue: "o1-pro")
    public static let o1 = Self(rawValue: "o1")
    public static let o1_mini = Self(rawValue: "o1-mini")

    // Others
    public static let gpt3_5_turbo = Self(rawValue: "gpt-3.5-turbo")

    public var apiMode: LLMOpenAIAPIMode {
        Self.chatCompletionModelIds.contains(rawValue) ? .chatCompletions : .responses
    }

    public var supportsReasoningSummary: Bool {
        guard apiMode == .responses else {
            return false
        }
        // `gpt-5-chat-latest` is the non-reasoning chat variant, and does not emit summaries.
        guard rawValue != Self.gpt5_chat.rawValue else {
            return false
        }
        return ["o1", "o3", "o4", "gpt-5"].contains { rawValue.hasPrefix($0) }
    }
}
