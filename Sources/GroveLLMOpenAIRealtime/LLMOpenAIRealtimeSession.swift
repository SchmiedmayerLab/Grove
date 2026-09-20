//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

package import Atomics
public import Foundation
import GeneratedOpenAIClient
import GroveChat
import GroveFoundation
import GroveKeychainStorage
public import GroveLLM
import OpenAPIRuntime
import OpenAPIURLSession
package import os

/// Represents an ``LLMOpenAIRealtimeSchema`` in execution.
///
/// The ``LLMOpenAIRealtimeSession`` is the executable version of the OpenAI Realtime LLM containing context and state as defined by the ``LLMOpenAIRealtimeSchema``.
/// It provides access to realtime models from OpenAI, such as gpt-realtime  or GPT-4o Realtime.
/// Also provides a way to transcribe those conversations using models such as GPT-4o Transcribe or Whisper.
///
/// A text inference is started by ``LLMOpenAIRealtimeSession/generate()``, returning an `AsyncThrowingStream` and can be cancelled via ``LLMOpenAIRealtimeSession/cancel()``.
/// The ``LLMOpenAIRealtimeSession`` exposes the user and assistant's audio transcripts via the ``LLMOpenAIRealtimeSession/context`` property, containing all the transcript history with the Realtime API.
///
/// - Warning: The ``LLMOpenAIRealtimeSession`` shouldn't be created manually but always through the ``LLMOpenAIRealtimePlatform`` via the `LLMRunner`.
///
/// - Tip: ``LLMOpenAIRealtimeSession`` also enables the function calling mechanism to establish a structured, bidirectional, and reliable communication
///   between the OpenAI LLMs and external tools. For details, refer to `LLMTool` and `LLMTool/Parameter` from GroveLLMOpenAI, or see GroveLLMOpenAI's FunctionCalling documentation.
///
/// - Tip: For more information, refer to the documentation of the `LLMSession` from GroveLLM.
///
/// ## Streams
/// - ``generate()``: Starts a text response and returns an `AsyncThrowingStream` of token deltas. Finishes when the response completes.
/// - ``listen()``: Returns an `AsyncThrowingStream` of PCM16 audio (24 kHz sample rate) for the assistant's speech output. Lasts for the lifetime of the session.
///
/// ### Usage
///
/// The example below demonstrates a minimal usage of the ``LLMOpenAIRealtimeSession`` via the `LLMRunner`.
///
/// ```swift
/// import GroveLLM
/// import GroveLLMOpenAIRealtime
/// import SwiftUI
///
/// struct LLMOpenAIRealtimeDemoView: View {
///     @Environment(LLMRunner.self) var runner
///     @State var responseText = ""
///
///     var body: some View {
///         Text(responseText)
///             .task {
///                 // Instantiate the `LLMOpenAIRealtimeSchema` to an `LLMOpenAIRealtimeSession` via the `LLMRunner`.
///                 let llmSession: LLMOpenAIRealtimeSession = runner(
///                     with: LLMOpenAIRealtimeSchema(
///                         parameters: .init(
///                             modelType: .gpt_realtime,
///                             systemPrompt: "You're a helpful assistant that answers questions from users.",
///                             turnDetectionSettings: .semantic(),
///                             transcriptionSettings: .init(model: .gpt4oTranscribe)
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
///
/// User audio input can be provided via ``appendUserAudio(_:)`` with 24 kHz PCM16 data.
/// When ``LLMRealtimeTurnDetectionSettings`` is configured through ``LLMOpenAIRealtimeParameters``, calling ``endUserTurn()`` is not required.
/// Otherwise, ``endUserTurn()`` can be used to explicitly trigger an assistant response.
///
/// The assistant's audio can be obtained as PCM16 at 24 kHz by calling ``listen()``:
/// ```swift
/// for try await pcm16 in try await llmSession.listen() {
///     someAudioBuffer.append(pcm16)
/// }
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
@Observable
public final class LLMOpenAIRealtimeSession: LLMSession, SchemaProvidingLLMSession, Sendable {
    /// A Swift Logger that logs important information from the ``LLMOpenAIRealtimeSession``.
    package static let logger = Logger(subsystem: "org.grovealliance", category: "GroveLLMOpenAIRealtime")

    let platform: LLMOpenAIRealtimePlatform
    package let schema: LLMOpenAIRealtimeSchema
    let keychainStorage: KeychainStorage
    
    /// Handles websockets connection with OpenAI Realtime API
    let apiConnection = LLMOpenAIRealtimeConnection()
    /// Tracks pending user-audio transcripts across the whole connection, shared by all tool grace-period waits
    /// across `generate()` calls. `stopEventHandling()` replaces it before setup/reconnect, on cancellation,
    /// and when the event listener ends or fails. Already queued actor calls and pending waits retain the old
    /// instance, isolating cancelled listeners from the next connection's transcript state. Within a connection,
    /// disabling input transcription resets the existing tracker in place.
    @MainActor var transcripts = UserTranscriptTracker()
    @MainActor var transcribesUserAudio = false
    @MainActor var assistantTranscripts = RealtimeAssistantTranscripts()
    @MainActor var eventHandlingId = UUID()
    @MainActor var eventTask: Task<Void, Never>?
    @MainActor var toolTasks: [String: ToolTask] = [:]
    @MainActor var activeGenerations: Set<String> = []

    @MainActor public var state: LLMState = .uninitialized
    @MainActor public var context: LLMContext = []
    let setupSemaphore = AsyncSemaphore(value: 1) // Max 1 task setting up
    package let toolCallCounter = Atomics.ManagedAtomic<Int>(0)
    package let toolCallCompletionState = LLMState.ready

    /// Creates an instance of a ``LLMOpenAISession`` responsible for LLM inference.
    ///
    /// - Parameters:
    ///   - platform: Reference to the ``LLMOpenAIRealtimePlatform`` where the ``LLMOpenAIRealtimeSession`` is running on.
    ///   - schema: The configuration of the OpenAI LLM expressed by the ``LLMOpenAIRealtimeSchema``.
    ///   - keychainStorage: Reference to the `KeychainStorage` from `GroveStorage` in order to securely persist the token.
    ///
    /// - Important: Only the ``LLMOpenAIRealtimePlatform`` should create an instance of ``LLMOpenAIRealtimeSession``.
    init(_ platform: LLMOpenAIRealtimePlatform, schema: LLMOpenAIRealtimeSchema, keychainStorage: KeychainStorage) {
        self.platform = platform
        self.schema = schema
        self.keychainStorage = keychainStorage
    }

    /// Starts an assistant response and streams text deltas.
    ///
    /// This method sends the latest user message in the ``LLMOpenAIRealtimeSession/context`` to the Realtime API, then triggers the model to respond.
    /// It returns an `AsyncThrowingStream` that yields only this generation's text, including responses after tool calls.
    /// Automatic voice responses and interjections remain available through the session's audio stream and context.
    ///
    /// - Returns: An `AsyncThrowingStream` of `String` token deltas. The stream finishes when its final response completes.
    ///   Cancelled, failed, and incomplete responses terminate the stream with an error, even when they contain no text.
    @discardableResult
    public func generate() async -> AsyncThrowingStream<String, any Error> {
        let requestId = UUID().uuidString

        return AsyncThrowingStream { [apiConnection] continuation in
            let task = Task {
                do {
                    try await self.ensureSetup()
                    try Task.checkCancellation()
                    await self.registerGeneration(requestId)
                    let connectionId = await apiConnection.connectionId

                    // Subscribe before sending: even a fast refusal must reach this generation.
                    let events = await apiConnection.events()
                    let conversationEventId = UUID().uuidString

                    try await self.requestGeneration(requestId: requestId, conversationEventId: conversationEventId, connectionId: connectionId)

                    let response = Self.textResponse(from: events, requestId: requestId, conversationEventId: conversationEventId)
                    for try await delta in response {
                        continuation.yield(delta)
                    }
                    continuation.finish() // in case `events()` stream finished
                } catch {
                    continuation.finish(throwing: error) // propagate upstream error
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
                Task { @MainActor in self.finishGeneration(requestId) }
            }
        }
    }
    
    /// Closes the realtime connection.
    ///
    /// Calling this function ends any active streams.
    public func cancel() {
        Task { @MainActor [weak self, apiConnection] in
            self?.stopEventHandling()
            self?.state = .uninitialized
            await apiConnection.cancel()
        }
    }

    deinit {
        self.cancel()
    }
}
