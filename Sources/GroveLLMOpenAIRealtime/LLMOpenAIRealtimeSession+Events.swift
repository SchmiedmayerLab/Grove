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
    func listenToLLMEvents(
        _ eventStream: AsyncThrowingStream<LLMRealtimeAudioEvent, any Error>,
        connectionId: UUID,
        broadcaster: EventBroadcaster<LLMRealtimeAudioEvent>
    ) {
        let handlingId = eventHandlingId
        eventTask = Task { [weak self] in
            do {
                for try await event in eventStream {
                    guard let self, !Task.isCancelled, self.eventHandlingId == handlingId else {
                        return
                    }
                    await self.handle(event, connectionId: connectionId, broadcaster: broadcaster, handlingId: handlingId)
                }
            } catch {
                guard let self, !Task.isCancelled, self.eventHandlingId == handlingId else {
                    return
                }
                Self.logger.error("GroveLLMOpenAIRealtime: Encountered error: \(error)")
                self.state = .error(error: (error as? any LLMError) ?? LLMOpenAIError.connectivityIssues(error))
                self.stopEventHandling()
                await self.apiConnection.cancel()
                return
            }
            if let self, self.eventHandlingId == handlingId {
                self.stopEventHandling()
                self.state = .uninitialized
            }
        }
    }

    @MainActor
    // swiftlint:disable:next cyclomatic_complexity
    private func handle(
        _ event: LLMRealtimeAudioEvent,
        connectionId: UUID,
        broadcaster: EventBroadcaster<LLMRealtimeAudioEvent>,
        handlingId: UUID
    ) async {
        let shouldInject = schema.injectIntoContext
        if shouldInject {
            assistantTranscripts.consume(event, context: &context)
        }
        switch event {
        case .inputTranscriptionConfigured(let enabled):
            transcribesUserAudio = enabled
            if !enabled {
                await transcripts.reset()
            }
        case .userTranscriptDelta(let content) where shouldInject:
            handleTranscript(itemId: content.itemId, content: content.delta, isComplete: false)
        case .userTranscriptDone(let content):
            if shouldInject {
                // A transcriber that sends no deltas delivers the words here, all at once.
                handleTranscript(itemId: content.itemId, content: "", isComplete: true, transcript: content.transcript)
            }
            // Release tools only after the final words are available in the context.
            await transcripts.complete(content.itemId)
        case .userTranscriptFailed(let content):
            await transcripts.complete(content.itemId)
        case .speechStopped(let content):
            await expectTranscript(itemId: content.itemId, handlingId: handlingId)
        case .userAudioCommitted(let itemId):
            // Manual turn detection sends committed without a preceding speech_stopped event.
            await expectTranscript(itemId: itemId, handlingId: handlingId)
        case .responseDone(let response) where response.status == .completed && !response.functionCalls.isEmpty:
            startToolContinuation(response, connectionId: connectionId, broadcaster: broadcaster)
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
    
    /// When a turn ends, append a user message before the assistant responds, and wait for its transcript.
    ///
    /// Use the configuration confirmed by the server, since locally supplied settings are ignored in server mode.
    @MainActor
    private func expectTranscript(itemId: String, handlingId: UUID) async {
        guard transcribesUserAudio else {
            return
        }
        await transcripts.expect(itemId)
        guard !Task.isCancelled, handlingId == eventHandlingId else {
            return
        }
        let contentUUID = UUID.deterministic(from: itemId)
        guard schema.injectIntoContext, !context.contains(where: { $0.id == contentUUID }) else {
            return
        }
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
}
