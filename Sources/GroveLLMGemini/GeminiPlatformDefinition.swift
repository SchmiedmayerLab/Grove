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


/// Defines the Gemini LLM platform.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct GeminiPlatformDefinition: LLMOpenAILikePlatformDefinition {
    public struct ModelType: LLMOpenAILikePlatformModelType {
        public let rawValue: String
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    public static let platformName = "Gemini"
    public static let platformServiceIdentifier = "generativelanguage.googleapis.com"

    public static let defaultServerUrl = URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!

    public static let platformDeveloperConsoleUrl = URL(string: "https://aistudio.google.com/app/api-keys")
}


// MARK: Type Specializations

/// Represents the configuration of the Grove ``LLMGeminiPlatform``.
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias LLMGeminiPlatformConfiguration = LLMOpenAILikePlatformConfiguration<GeminiPlatformDefinition>


/// Represents the parameters of a Gemini LLM model.
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias LLMGeminiParameters = LLMOpenAILikeParameters<GeminiPlatformDefinition>


/// LLM execution platform of a ``LLMGeminiSchema``.
///
/// - Note: This type behaves identical to GroveLLMOpenAI's `LLMOpenAIPlatform`, except that it interacts with Gemini's APIs instead of OpenAI's; see the [`LLMOpenAIPlatform`](../GroveLLMOpenAI/GroveLLMOpenAI.docc/GroveLLMOpenAI.md) documentation for further documentation.
///
/// ### Usage
///
/// The example below demonstrates the setup of the ``LLMGeminiPlatform`` within the Grove `Configuration`.
/// ```swift
/// class TestAppDelegate: GroveAppDelegate {
///     override var configuration: Configuration {
///         Configuration {
///             LLMRunner {
///                 LLMGeminiPlatform()
///             }
///         }
///     }
/// }
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias LLMGeminiPlatform = LLMOpenAILikePlatform<GeminiPlatformDefinition>


/// Defines the type and configuration of the ``LLMGeminiSession``.
///
/// The ``LLMGeminiSchema`` is used as a configuration for the to-be-used LLMGeminiPlatform LLM. It contains all information necessary for the creation of an executable ``LLMGeminiSession``.
/// It is bound to a ``LLMGeminiPlatform`` that is responsible for turning the ``LLMGeminiSchema`` to an ``LLMGeminiSession``.
///
/// - Note: This type behaves identical to GroveLLMOpenAI's `LLMOpenAISchema`, except that it interacts with Gemini's APIs instead of OpenAI's; see the [`LLMOpenAISchema`](../GroveLLMOpenAI/GroveLLMOpenAI.docc/GroveLLMOpenAI.md) documentation for further documentation.
///
/// - Tip: ``LLMGeminiSchema`` also enables the function calling mechanism to establish a structured, bidirectional, and reliable communication between the ``LLMGeminiPlatform`` LLMs and external tools.
///     For more details, refer to the [`LLMOpenAISchema`](../GroveLLMOpenAI/GroveLLMOpenAI.docc/GroveLLMOpenAI.md) documentation.
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias LLMGeminiSchema = LLMOpenAILikeSchema<GeminiPlatformDefinition>


/// Represents an ``LLMGeminiSchema`` in execution.
///
/// The ``LLMGeminiSession`` is the executable version of the LLMGeminiPlatform LLM containing context and state as defined by the ``LLMGeminiSchema``.
/// It provides access to text-based models from Gemini.
///
/// - Note: This type behaves identical to GroveLLMOpenAI's `LLMOpenAISession`, except that it interacts with Gemini's APIs instead of OpenAI's; see the [`LLMOpenAISession`](../GroveLLMOpenAI/GroveLLMOpenAI.docc/GroveLLMOpenAI.md) documentation for further documentation.
///
///
/// ### Usage
///
/// The example below demonstrates a minimal usage of the ``LLMGeminiSession`` via the `LLMRunner`.
///
/// ```swift
/// import GroveLLM
/// import GroveLLMGemini
/// import SwiftUI
///
/// struct LLMGeminiDemoView: View {
///     @Environment(LLMRunner.self) var runner
///     @State var responseText = ""
///
///     var body: some View {
///         Text(responseText)
///             .task {
///                 // Instantiate the `LLMGeminiSchema` to an `LLMGeminiSession` via the `LLMRunner`.
///                 let llmSession: LLMGeminiSession = runner(
///                     with: LLMGeminiSchema(
///                         parameters: .init(
///                             modelType: .gemini3_1_pro,
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
public typealias LLMGeminiSession = LLMOpenAILikeSession<GeminiPlatformDefinition>


#if canImport(SwiftUI)
/// View to display an onboarding step for the user to enter a Gemini API Key.
///
/// - Warning: Ensure that the ``LLMGeminiPlatform`` is specified within the Grove `Configuration` when using this view in the onboarding flow.
///
/// - Important: Only use this if the corresponding LLM platform's config's auth token is set to `RemoteLLMInferenceAuthToken/keychain(_:CredentialsTag)`
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias LLMGeminiAPITokenOnboardingStep = LLMOpenAILikeAPITokenOnboardingStep<GeminiPlatformDefinition>


/// View to display an onboarding step for the user to select a Gemini model.
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias LLMGeminiModelOnboardingStep = LLMOpenAILikeModelOnboardingStep<GeminiPlatformDefinition>
#endif


#if canImport(Security)
public import GroveKeychainStorage


@available(iOS 18, macOS 15, watchOS 11, *)
extension CredentialsTag {
    /// The canonical credentials tag for the Gemini API key
    public static let geminiKey = Self.for(GeminiPlatformDefinition.self)
}
#endif


// MARK: Models

// swiftlint:disable identifier_name
@available(iOS 18, macOS 15, watchOS 11, *)
extension GeminiPlatformDefinition.ModelType {
    /// The default model to be used with Gemini.
    public static let `default`: Self = .gemini3_7_flash

    public static let wellKnownModels: [Self] = [ // swiftlint:disable:this missing_docs
        .gemini3_7_flash, .gemini3_6_flash, .gemini3_5_flash, .gemini3_5_flash_lite, .gemini3_1_flash_lite,
        .gemini3_1_pro_preview,
        .gemini2_5_pro, .gemini2_5_flash, .gemini2_5_flash_lite
    ]

    /// Gemini 3.7 Flash
    public static let gemini3_7_flash = Self(rawValue: "gemini-3.7-flash")
    /// Gemini 3.6 Flash
    public static let gemini3_6_flash = Self(rawValue: "gemini-3.6-flash")
    /// Gemini 3.5 Flash
    public static let gemini3_5_flash = Self(rawValue: "gemini-3.5-flash")
    /// Gemini 3.5 Flash Lite
    public static let gemini3_5_flash_lite = Self(rawValue: "gemini-3.5-flash-lite")
    /// Gemini 3.1 Flash Lite
    public static let gemini3_1_flash_lite = Self(rawValue: "gemini-3.1-flash-lite")

    /// Gemini 3.1 Pro, the most capable Gemini model. Google still ships it as a preview.
    public static let gemini3_1_pro_preview = Self(rawValue: "gemini-3.1-pro-preview")
    /// Gemini 3 Flash. Google still ships it as a preview.
    public static let gemini3_flash_preview = Self(rawValue: "gemini-3-flash-preview")

    @available(*, deprecated, renamed: "gemini3_1_pro_preview", message: "Google only serves Gemini 3.1 Pro as a preview.")
    public static let gemini3_1_pro = Self(rawValue: "gemini-3.1-pro-preview") // swiftlint:disable:this missing_docs

    @available(*, deprecated, renamed: "gemini3_1_pro_preview", message: "There is no Gemini 3 Pro; use Gemini 3.1 Pro.")
    public static let gemini3_pro = Self(rawValue: "gemini-3.1-pro-preview") // swiftlint:disable:this missing_docs

    @available(*, deprecated, renamed: "gemini3_flash_preview", message: "Google only serves Gemini 3 Flash as a preview.")
    public static let gemini3_flash = Self(rawValue: "gemini-3-flash-preview") // swiftlint:disable:this missing_docs

    /// Gemini 2.5 Pro
    public static let gemini2_5_pro = Self(rawValue: "gemini-2.5-pro")
    /// Gemini 2.5 Flash
    public static let gemini2_5_flash = Self(rawValue: "gemini-2.5-flash")
    /// Gemini 2.5 Flash Lite
    public static let gemini2_5_flash_lite = Self(rawValue: "gemini-2.5-flash-lite")

    public var supportsSamplingControls: Bool { // swiftlint:disable:this missing_docs
        // Google deprecated the sampling controls with the 3.5 Flash-Lite and 3.6 generation, in favour of a
        // reasoning effort. They are ignored there rather than rejected, and Google has said later models will
        // reject them, so nothing is gained by continuing to send them.
        ![Self.gemini3_7_flash, .gemini3_6_flash, .gemini3_5_flash_lite].contains(self)
    }
}
// swiftlint:enable identifier_name
