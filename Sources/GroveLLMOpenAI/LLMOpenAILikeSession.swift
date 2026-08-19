//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

package import Atomics
import Foundation
import GeneratedOpenAIClient
package import GroveFoundation
public import GroveLLM
public import Observation
import OpenAPIRuntime
import OpenAPIURLSession
import Synchronization

/// Represents an ``LLMOpenAILikeSchema`` in execution.
///
/// The ``LLMOpenAILikeSession`` is the executable version of the OpenAI LLM containing context and state as defined by the ``LLMOpenAILikeSchema``.
/// It provides access to text-based models from OpenAI, such as GPT-3.5 or GPT-4.
///
/// The inference is started by ``LLMOpenAILikeSession/generate()``, returning an `AsyncThrowingStream` and can be cancelled via ``LLMOpenAILikeSession/cancel()``.
/// The ``LLMOpenAISession`` exposes its current state via the ``LLMOpenAILikeSession/context`` property, containing all the conversational history with the LLM.
///
/// - Warning: The ``LLMOpenAILikeSession`` shouldn't be created manually but always through the ``LLMOpenAILikePlatform`` via the `LLMRunner`.
///
/// - Tip: ``LLMOpenAILikeSession`` also enables the function calling mechanism to establish a structured, bidirectional, and reliable communication between the OpenAI LLMs and external tools. For details, refer to ``LLMTool`` and ``LLMTool/Parameter`` or the <doc:ToolCalling> DocC article.
///
/// - Tip: For more information, refer to the documentation of the `LLMSession` from GroveLLM.
///
/// ### Usage
///
/// The example below demonstrates a minimal usage of the ``LLMOpenAILikeSession`` via the `LLMRunner`.
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
@Observable
public final class LLMOpenAILikeSession<
    PlatformDefinition: LLMOpenAILikePlatformDefinition
>: LLMSession, ToolCallLLMSession, SchemaProvidingLLMSession, Sendable {
    /// A Swift Logger that logs important information from the ``LLMOpenAISession``.
    package static var logger: Logger {
        Logger(subsystem: "org.grovealliance", category: "GroveLLMOpenAI")
    }
    
    let platform: LLMOpenAILikePlatform<PlatformDefinition>
    package let schema: LLMOpenAILikeSchema<PlatformDefinition>
    let keychainStorage: LLMCredentialStorage?
 
    private let client = Mutex<(any LLMOpenAIChatClientProtocol)?>(nil)
    /// Counter for tracking nested tool calls
    package let toolCallCounter = ManagedAtomic<Int>(0)
    package let toolCallCompletionState = LLMState.generating
    /// Holds the currently generating continuations so that we can cancel them if required.
    let continuationHolder = LLMInferenceQueueContinuationHolder()

    /// The state of the server-side Responses API conversation, guarded against the streaming task and the
    /// consuming task touching it concurrently — e.g. when a view disappears mid-generation.
    @ObservationIgnored let responsesConversation = Mutex(ResponsesConversationState())

    /// The ID of the last completed Responses API response. Visible for tests.
    var lastResponseId: String? {
        responsesConversation.withLock { $0.lastResponseId }
    }

    /// The API this session's inference is served over, after applying the platform's API mode policy.
    package var apiMode: LLMOpenAIAPIMode {
        platform.configuration.apiMode.resolve(for: schema.parameters.modelType)
    }

    @MainActor public var state: LLMState = .uninitialized
    @MainActor public var context: LLMContext = []

    var openAiClient: any LLMOpenAIChatClientProtocol {
        get {
            let client = self.client.withLock { $0 }

            guard let client else {
                fatalError("""
                GroveLLMOpenAI: Illegal Access - Tried to access the wrapped OpenAI client of `LLMOpenAISession` before being initialized.
                Ensure that the `LLMOpenAIPlatform` is passed to the `LLMRunner` within the Grove `Configuration`.
                """)
            }
            return client
        }

        set {
            client.withLock { $0 = newValue }
        }
    }
    
    
    /// Creates an instance of a ``LLMOpenAISession`` responsible for LLM inference.
    ///
    /// - Parameters:
    ///   - platform: Reference to the ``LLMOpenAIPlatform`` where the ``LLMOpenAISession`` is running on.
    ///   - schema: The configuration of the OpenAI LLM expressed by the ``LLMOpenAISchema``.
    ///   - keychainStorage: The credential store a keychain-backed auth token is read from; `nil` where the platform has no Keychain.
    ///
    /// - Important: Only the ``LLMOpenAIPlatform`` should create an instance of ``LLMOpenAISession``.
    init(
        _ platform: LLMOpenAILikePlatform<PlatformDefinition>,
        schema: LLMOpenAILikeSchema<PlatformDefinition>,
        keychainStorage: LLMCredentialStorage?
    ) {
        self.platform = platform
        self.schema = schema
        self.keychainStorage = keychainStorage
    }
    
    
    @discardableResult
    public func generate() async throws -> AsyncThrowingStream<String, any Error> {
        // Inject system prompts into context
        if await self.context.isEmpty {
            await MainActor.run {
                for prompt in self.schema.parameters.systemPrompts {
                    self.context.append(systemMessage: prompt, to: .leadingSystemMessages)
                }
            }
        }

        return try self.platform.queue.submit { continuation in
            // starts tracking the continuation for cancellation
            let continuationObserver = ContinuationObserver(track: continuation)
            defer {
                // To be on the safe side, finish the continuation (has no effect if multiple finish calls)
                continuationObserver.continuation.finish()
            }

            // Retains the continuation during inference for potential cancellation
            await self.continuationHolder.withContinuationHold(continuation: continuation) {
                if continuationObserver.isCancelled {
                    Self.logger.warning("GroveLLMOpenAI: Generation cancelled by the user.")
                    return
                }

                // Setup the model, if not already done
                if self.client.withLock({ $0 == nil }) {
                    guard await self.setup(with: continuationObserver) else {
                        return
                    }
                }

                // Execute the inference using the API the selected model is served over
                switch self.apiMode {
                case .chatCompletions:
                    await self._generate(with: continuationObserver)
                case .responses:
                    await self._generateWithResponses(with: continuationObserver)
                }
            }
        }
    }
    
    public func cancel() {
        // cancel all currently generating continuations
        self.continuationHolder.cancelAll()
    }
    
    deinit {
        self.cancel()
    }
}
