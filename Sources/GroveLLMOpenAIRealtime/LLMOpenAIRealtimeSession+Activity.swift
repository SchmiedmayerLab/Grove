//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// What a session notices about the conversation beyond its words and audio, for a client to react to.
@available(iOS 18, macOS 15, watchOS 11, *)
public enum LLMOpenAIRealtimeActivity: Sendable {
    /// The participant began talking; audio the client still holds for the assistant is stale from here on.
    case participantStartedSpeaking
    case participantStoppedSpeaking
    /// The server finished sending the assistant's audio; the device may still be playing it.
    case assistantFinishedSpeaking
    /// The server refused one event, with its error code if it gave one; the session is still up.
    case serverRefused(code: String?, message: String)
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMOpenAIRealtimeSession {
    /// Streams the conversation's activity for as long as the session runs.
    public func activity() async -> AsyncThrowingStream<LLMOpenAIRealtimeActivity, any Error> {
        AsyncThrowingStream { [apiConnection] continuation in
            let task = Task {
                do {
                    try await self.ensureSetup()
                    for try await event in await apiConnection.events() {
                        switch event {
                        case .speechStarted:
                            continuation.yield(.participantStartedSpeaking)
                        case .speechStopped:
                            continuation.yield(.participantStoppedSpeaking)
                        case .audioDone:
                            continuation.yield(.assistantFinishedSpeaking)
                        case .serverError(let payload):
                            continuation.yield(.serverRefused(code: payload.code, message: payload.message))
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// Has the assistant say something short right now, outside the conversation, for example to bridge a wait.
    /// The model does not treat it as part of the exchange; the words still appear in the context as an assistant line.
    public func interject(_ instructions: String) async throws {
        try await ensureSetup()
        try await apiConnection.requestInterjection(instructions)
    }
}
