//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMOpenAIRealtimeSession {
    /// A request refusal ends only its caller's stream; the connection and its other subscribers stay live.
    static func textResponse(
        from events: AsyncThrowingStream<LLMRealtimeAudioEvent, any Error>,
        requestId: String,
        conversationEventId: String
    ) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var requestSent = false
                do {
                    for try await event in events {
                        switch event {
                        case .responseRequested(let eventId) where eventId == requestId:
                            requestSent = true
                        case .assistantTranscriptDelta(let delta) where requestSent:
                            continuation.yield(delta)
                        case .assistantTranscriptDone where requestSent:
                            continuation.finish()
                            return
                        case .serverError(let error) where error.event_id == requestId || error.event_id == conversationEventId:
                            throw LLMOpenAIRealtimeConnection.RealtimeError.openAIError(error: error)
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
