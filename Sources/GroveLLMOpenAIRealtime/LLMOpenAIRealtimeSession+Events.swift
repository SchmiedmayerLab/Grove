//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GeneratedOpenAIClient
import GroveLLM
import GroveLLMOpenAI


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMOpenAIRealtimeSession: ToolCallLLMSession {
    @MainActor
    func listenToLLMEvents() {
        Task { [weak self] in
            guard let eventStream = await self?.apiConnection.events() else {
                Self.logger.error("GroveLLMOpenAIRealtime: No self in listenToLLMEvents...")
                return
            }
            do {
                for try await event in eventStream {
                    await self?.handle(event)
                }
            } catch let error as any LLMError {
                Self.logger.error("GroveLLMOpenAIRealtime: Encountered LLM Error: \(error)")
                self?.state = .error(error: error)
                // The next setup opens a fresh socket; the broken one must not keep running underneath it.
                await self?.apiConnection.cancel()
            } catch {
                Self.logger.error("GroveLLMOpenAIRealtime: Encountered unknown error: \(error)")
                self?.state = .error(error: LLMOpenAIError.connectivityIssues(error))
                await self?.apiConnection.cancel()
            }
        }
    }

    @MainActor
    private func handle(_ event: LLMRealtimeAudioEvent) async { // swiftlint:disable:this cyclomatic_complexity
        let shouldInject = schema.injectIntoContext
        switch event {
        case .assistantTranscriptDelta(let content) where shouldInject:
            context.append(assistantOutputDelta: content, isComplete: false, interactionId: nil)
        case .assistantTranscriptDone where shouldInject:
            context.markAssistantOutputCompleted()
        case .userTranscriptDelta(let content) where shouldInject:
            handleTranscript(itemId: content.itemId, content: content.delta, isComplete: false)
        case .userTranscriptDone(let content):
            await transcripts.complete(content.itemId)
            if shouldInject {
                // A transcriber that sends no deltas delivers the words here, all at once.
                handleTranscript(itemId: content.itemId, content: "", isComplete: true, transcript: content.transcript)
            }
        case .userTranscriptFailed(let content):
            await transcripts.complete(content.itemId)
        case .speechStopped(let content):
            if schema.parameters.transcriptionSettings != nil {
                await transcripts.expect(content.itemId)
            }
            if shouldInject {
                handleSpeechStopped(itemId: content.itemId)
            }
        case .functionCallRequested(let functionCall):
            Task {
                await self.handleFunctionCall(functionCall: functionCall)
            }
        default:
            break
        }
    }
    
    /// Updates an existing context message by appending content, and optionally marking it as complete.
    ///
    /// If no message in the context has a UUID matching the deterministic UUID derived from `itemId`,
    /// this function does nothing and the content is ignored.
    @MainActor
    private func handleTranscript(itemId: String, content: String, isComplete: Bool, transcript: String? = nil) {
        let contentUUID = UUID.deterministic(from: itemId)
        let existingTranscriptIdx = self.context.firstIndex {
            $0.id == contentUUID
        }

        guard let existingTranscriptIdx = existingTranscriptIdx else {
            return
        }

        let existingMessage = self.context[existingTranscriptIdx]
        let accumulated = existingMessage.content + content
        let final = transcript.map { $0.isEmpty ? accumulated : $0 } ?? accumulated

        self.context[existingTranscriptIdx] = .init(
            id: contentUUID,
            date: existingMessage.date,
            role: .user,
            content: final,
            complete: isComplete
        )
    }
    
    /// When speech stops, directly append an empty user message to ensure it appears before any assistant
    /// messages in the context. This message then gets completed using the `.userTranscriptDelta` event
    ///
    /// - Note: If no transcription settings are configured inside the LLMSession's schema parameter, no message is appended to the context.
    @MainActor
    private func handleSpeechStopped(itemId: String) {
        guard self.schema.parameters.transcriptionSettings != nil else {
            return
        }

        let contentUUID = UUID.deterministic(from: itemId)
        self.context.append(
            .init(
                id: contentUUID,
                date: Date.now,
                role: .user,
                content: "",
                complete: false
            )
        )
    }
    
    @MainActor
    private func handleFunctionCall(functionCall: LLMOpenAIStreamResult.FunctionCall) async {
        typealias ConversationItemCreateEvent = Components.Schemas.RealtimeClientEventConversationItemCreate

        // The call and the transcript of the turn it answers arrive independently; a tool that reads the
        // participant's own words from the context needs the transcript to be there first.
        if let gracePeriod = schema.parameters.transcriptGracePeriod {
            await transcripts.waitUntilSettled(timeout: gracePeriod)
        }
        let functionCallResponse = try? await self.callFunction(
            availableFunctions: schema.functions,
            functionCallArgs: functionCall,
            failureHandling: .returnErrorInResponse
        )

        guard let functionCallResponse = functionCallResponse else {
            // Should never happen while having `failureHandling: .returnErrorInResponse`
            Self.logger.warning("LLMOpenAIRealtimeSession: callFunction() threw an error.")
            return
        }

        do {
            try await self.apiConnection.sendMessage(
                ConversationItemCreateEvent(
                    _type: .conversation_period_item_period_create,
                    item: .init(
                        value5: .init(
                            _type: .function_call_output,
                            call_id: functionCallResponse.functionID,
                            output: functionCallResponse.response
                        )
                    )
                )
            )
            
            try await self.apiConnection.requestResponse(toolChoice: schema.parameters.followUpToolChoice)
        } catch {
            Self.logger.error("LLMOpenAIRealtimeSession: Function call failed due to API connection")
        }
    }
}
