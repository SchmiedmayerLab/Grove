//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
import FoundationModels
public import GroveLLM
import os


/// Represents an ``LLMFoundationModelsSchema`` in execution.
///
/// Inference is started by ``LLMFoundationModelsSession/generate()``, returning an `AsyncThrowingStream`, and can be
/// cancelled via ``LLMFoundationModelsSession/cancel()``.
///
/// - Warning: The session shouldn't be created manually, but always through the ``LLMFoundationModelsPlatform`` via
///   the `LLMRunner`.
///
/// ### Usage
///
/// ```swift
/// struct LLMFoundationModelsDemoView: View {
///     @Environment(LLMRunner.self) var runner
///     @State var responseText = ""
///
///     var body: some View {
///         Text(responseText)
///             .task {
///                 let session: LLMFoundationModelsSession = runner(
///                     with: LLMFoundationModelsSchema(
///                         modelType: .onDevice,
///                         systemPrompt: "You're a helpful assistant that answers questions from users."
///                     )
///                 )
///                 session.context.append(userMessage: "What is the capital of France?")
///
///                 for try await token in try await session.generate() {
///                     responseText.append(token)
///                 }
///             }
///     }
/// }
/// ```
@available(iOS 27, macOS 27, visionOS 27, *)
@Observable
public final class LLMFoundationModelsSession: LLMSession, SchemaProvidingLLMSession, Sendable {
    static var logger: Logger {
        Logger(subsystem: "org.grovealliance", category: "GroveLLMFoundationModels")
    }

    let platform: LLMFoundationModelsPlatform
    public let schema: LLMFoundationModelsSchema

    /// Holds the currently generating continuations so that we can cancel them if required.
    let continuationHolder = LLMInferenceQueueContinuationHolder()

    @MainActor public var state: LLMState = .uninitialized
    @MainActor public var context: LLMContext = []


    init(_ platform: LLMFoundationModelsPlatform, schema: LLMFoundationModelsSchema) {
        self.platform = platform
        self.schema = schema
    }


    @discardableResult
    public func generate() async throws -> AsyncThrowingStream<String, any Error> {
        try platform.queue.submit { continuation in
            let continuationObserver = ContinuationObserver(track: continuation)

            await self.continuationHolder.withContinuationHold(continuation: continuation) {
                await MainActor.run {
                    self.state = .loading
                }

                // The model may be missing entirely, and the failure is worth naming precisely rather than
                // surfacing whatever the first prompt happens to throw.
                if let error = await self.platform.availability(of: self.schema.modelType).error {
                    await self.finish(continuationObserver, with: error)
                    return
                }

                let request = await MainActor.run {
                    FoundationModelsRequest(
                        context: self.context,
                        systemPrompt: self.schema.systemPrompt,
                        includesImages: self.schema.modelType.supportsVision
                    )
                }

                await self.stream(request, into: continuationObserver)
            }
        }
    }

    public func cancel() {
        continuationHolder.cancelAll()
    }

    /// Runs one turn, forwarding the model's output as it arrives.
    private func stream(
        _ request: FoundationModelsRequest,
        into continuationObserver: ContinuationObserver<String, any Error>
    ) async {
        #if compiler(>=6.4)
        let session = LanguageModelSession(
            model: schema.modelType.languageModel,
            transcript: request.transcript
        )
        #else
        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            transcript: request.transcript
        )
        #endif

        await MainActor.run {
            self.state = .generating
        }

        do {
            // Snapshots carry the response so far rather than the newest piece of it, so the delta is what's new
            // since the previous snapshot.
            var delivered = ""
            for try await snapshot in session.streamResponse(to: request.prompt, options: schema.generationOptions) {
                guard !continuationObserver.isCancelled else {
                    break
                }
                let content = snapshot.content
                guard content.hasPrefix(delivered) else {
                    // The model revised what it had already emitted, which the incremental context cannot express.
                    Self.logger.warning("GroveLLMFoundationModels: Discarding a non-monotonic response snapshot.")
                    continue
                }
                let delta = String(content.dropFirst(delivered.count))
                guard !delta.isEmpty else {
                    continue
                }
                delivered = content
                continuationObserver.continuation.yield(delta)
                if schema.injectIntoContext {
                    await MainActor.run {
                        self.context.append(assistantOutputDelta: delta, isComplete: false)
                    }
                }
            }
        } catch {
            await finish(continuationObserver, with: LLMFoundationModelsError(error))
            return
        }

        continuationObserver.continuation.finish()
        await MainActor.run {
            if self.schema.injectIntoContext {
                self.context.markAssistantOutputCompleted()
            }
            self.state = .ready
        }
    }

    /// Ends the turn with the given error, both on the stream and in the session's state.
    private func finish(
        _ continuationObserver: ContinuationObserver<String, any Error>,
        with error: LLMFoundationModelsError
    ) async {
        Self.logger.error("GroveLLMFoundationModels: \(error.localizedDescription)")
        await MainActor.run {
            // Whatever streamed before the failure was already shown, so it is closed off rather than dropped.
            if self.schema.injectIntoContext {
                self.context.markAssistantOutputCompleted()
            }
            self.state = .error(error: error)
        }
        continuationObserver.continuation.finish(throwing: error)
    }
    deinit {
        cancel()
    }
}
