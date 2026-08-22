//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

public import Foundation
public import GroveLLMOpenAI


/// Defines the Anthropic LLM platform.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct AnthropicPlatformDefinition: LLMOpenAILikePlatformDefinition {
    public struct ModelType: LLMOpenAILikePlatformModelType {
        public let rawValue: String
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    public static let platformName = "Anthropic"
    public static let platformServiceIdentifier = "api.anthropic.com"

    public static let defaultServerUrl = URL(string: "https://api.anthropic.com/v1")!

    public static let platformDeveloperConsoleUrl = URL(string: "https://platform.claude.com/settings/keys")
}


// MARK: Type Specializations

/// Represents the configuration of the Grove ``LLMAnthropicPlatform``.
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias LLMAnthropicPlatformConfiguration = LLMOpenAILikePlatformConfiguration<AnthropicPlatformDefinition>


/// Represents the parameters of an Anthropic LLM model.
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias LLMAnthropicParameters = LLMOpenAILikeParameters<AnthropicPlatformDefinition>


/// LLM execution platform of an Anthropic ``LLMAnthropicSchema``.
///
/// - Note: This type behaves identical to GroveLLMOpenAI's `LLMOpenAIPlatform`, except that it interacts with Anthropic's APIs instead of OpenAI's; see the [`LLMOpenAIPlatform`](../GroveLLMOpenAI/GroveLLMOpenAI.docc/GroveLLMOpenAI.md) documentation for further documentation.
///
/// ### Usage
///
/// The example below demonstrates the setup of the ``LLMAnthropicPlatform`` within the Grove `Configuration`.
/// ```swift
/// class TestAppDelegate: GroveAppDelegate {
///     override var configuration: Configuration {
///         Configuration {
///             LLMRunner {
///                 LLMAnthropicPlatform()
///             }
///         }
///     }
/// }
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias LLMAnthropicPlatform = LLMOpenAILikePlatform<AnthropicPlatformDefinition>


/// Defines the type and configuration of the ``LLMAnthropicSession``.
///
/// The ``LLMAnthropicSchema`` is used as a configuration for the to-be-used LLMAnthropicPlatform LLM. It contains all information necessary for the creation of an executable ``LLMAnthropicSession``.
/// It is bound to a ``LLMAnthropicPlatform`` that is responsible for turning the ``LLMAnthropicSchema`` to an ``LLMAnthropicSession``.
///
/// - Note: This type behaves identical to GroveLLMOpenAI's `LLMOpenAISchema`, except that it interacts with Anthropic's APIs instead of OpenAI's; see the [`LLMOpenAISchema`](../GroveLLMOpenAI/GroveLLMOpenAI.docc/GroveLLMOpenAI.md) documentation for further documentation.
///
/// - Tip: ``LLMAnthropicSchema`` also enables the function calling mechanism to establish a structured, bidirectional, and reliable communication between the ``LLMAnthropicPlatform`` LLMs and external tools.
///     For more details, refer to the [`LLMOpenAISchema`](../GroveLLMOpenAI/GroveLLMOpenAI.docc/GroveLLMOpenAI.md) documentation.
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias LLMAnthropicSchema = LLMOpenAILikeSchema<AnthropicPlatformDefinition>


/// Represents an ``LLMAnthropicSchema`` in execution.
///
/// The ``LLMAnthropicSession`` is the executable version of the LLMAnthropicPlatform LLM containing context and state as defined by the ``LLMAnthropicSchema``.
/// It provides access to text-based models from Anthropic, such as Claude Opus or Sonnet.
///
/// - Note: This type behaves identical to GroveLLMOpenAI's `LLMOpenAISession`, except that it interacts with Anthropic's APIs instead of OpenAI's; see the [`LLMOpenAISession`](../GroveLLMOpenAI/GroveLLMOpenAI.docc/GroveLLMOpenAI.md) documentation for further documentation.
///
///
/// ### Usage
///
/// The example below demonstrates a minimal usage of the ``LLMAnthropicSession`` via the `LLMRunner`.
///
/// ```swift
/// import GroveLLM
/// import GroveLLMAnthropic
/// import SwiftUI
///
/// struct LLMAnthropicDemoView: View {
///     @Environment(LLMRunner.self) var runner
///     @State var responseText = ""
///
///     var body: some View {
///         Text(responseText)
///             .task {
///                 // Instantiate the `LLMAnthropicSchema` to an `LLMAnthropicSession` via the `LLMRunner`.
///                 let llmSession: LLMAnthropicSession = runner(
///                     with: LLMAnthropicSchema(
///                         parameters: .init(
///                             modelType: .opus4_6,
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
public typealias LLMAnthropicSession = LLMOpenAILikeSession<AnthropicPlatformDefinition>


#if canImport(SwiftUI)
/// View to display an onboarding step for the user to enter an Anthropic API Key.
///
/// - Warning: Ensure that the ``LLMAnthropicPlatform`` is specified within the Grove `Configuration` when using this view in the onboarding flow.
///
/// - Important: Only use this if the corresponding LLM platform's config's auth token is set to `RemoteLLMInferenceAuthToken/keychain(_:CredentialsTag)`
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias LLMAnthropicAPITokenOnboardingStep = LLMOpenAILikeAPITokenOnboardingStep<AnthropicPlatformDefinition>


/// View to display an onboarding step for the user to select an Anthropic model.
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias LLMAnthropicModelOnboardingStep = LLMOpenAILikeModelOnboardingStep<AnthropicPlatformDefinition>
#endif


#if canImport(Security)
public import GroveKeychainStorage


@available(iOS 18, macOS 15, watchOS 11, *)
extension CredentialsTag {
    /// The canonical credentials tag for the Anthropic API key
    public static let anthropicKey = Self.for(AnthropicPlatformDefinition.self)
}
#endif


// MARK: Models

// swiftlint:disable identifier_name
@available(iOS 18, macOS 15, watchOS 11, *)
extension AnthropicPlatformDefinition.ModelType {
    /// The default model to be used with Anthropic.
    public static let `default`: Self = .opus5

    public static let wellKnownModels: [Self] = [ // swiftlint:disable:this missing_docs
        .opus5, .sonnet5, .haiku4_5,
        .opus4_8, .opus4_7, .opus4_6, .sonnet4_6
    ]

    /// Claude Opus 5
    public static let opus5 = Self(rawValue: "claude-opus-5")
    /// Claude Sonnet 5
    public static let sonnet5 = Self(rawValue: "claude-sonnet-5")
    /// Claude Haiku 4.5
    public static let haiku4_5 = Self(rawValue: "claude-haiku-4-5")

    /// Claude Opus 4.8
    public static let opus4_8 = Self(rawValue: "claude-opus-4-8")
    /// Claude Opus 4.7
    public static let opus4_7 = Self(rawValue: "claude-opus-4-7")
    /// Claude Opus 4.6
    public static let opus4_6 = Self(rawValue: "claude-opus-4-6")
    /// Claude Sonnet 4.6
    public static let sonnet4_6 = Self(rawValue: "claude-sonnet-4-6")

    @available(*, deprecated, renamed: "haiku4_5", message: "The model is Claude Haiku 4.5; the old name was a typo.")
    public static let haiku4_6 = Self(rawValue: "claude-haiku-4-5") // swiftlint:disable:this missing_docs

    public var supportsSamplingControls: Bool { // swiftlint:disable:this missing_docs
        // Anthropic stopped accepting non-default sampling from Opus 4.7 onwards, and the current Sonnet and Haiku
        // generations followed; asking for one is a `400`. Steer these models through the prompt instead.
        ![Self.opus5, .sonnet5, .opus4_8, .opus4_7].contains(self)
    }
}
// swiftlint:enable identifier_name
