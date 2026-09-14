//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMOpenAIRealtimeConnection {
    struct IdleWaiter {
        let id: UUID
        let eventId: String
        let continuation: CheckedContinuation<Void, Never>
    }

    var isResponseIdle: Bool {
        activeResponses.isEmpty && pendingResponseRequests.isEmpty
    }

    /// Requests the model's next response, optionally without letting it call tools.
    func requestResponse(toolChoice: LLMOpenAIRealtimeParameters.FollowUpToolChoice = .auto) async throws {
        struct ResponseCreate: Encodable {
            struct Response: Encodable {
                // swiftlint:disable:next identifier_name
                let tool_choice: String
            }

            let type = "response.create"
            // swiftlint:disable:next identifier_name
            let event_id: String
            let response: Response?
        }
        let eventId = UUID().uuidString
        await waitUntilResponseIdle(reserving: eventId)
        if Task.isCancelled {
            withdraw(eventId)
            throw CancellationError()
        }
        try await send(ResponseCreate(
            event_id: eventId,
            response: toolChoice == .auto ? nil : ResponseCreate.Response(tool_choice: toolChoice.rawValue)
        ), as: eventId)
    }

    /// Has the model say something outside the conversation, so a wait can be bridged without touching the transcript.
    func requestInterjection(_ instructions: String) async throws {
        struct ResponseCreate: Encodable {
            struct Response: Encodable {
                // swiftlint:disable identifier_name
                let conversation = "none"
                let tool_choice = "none"
                let output_modalities = ["audio"]
                // swiftlint:enable identifier_name
                let instructions: String
            }

            let type = "response.create"
            // swiftlint:disable:next identifier_name
            let event_id: String
            let response: Response
        }
        let eventId = UUID().uuidString
        await waitUntilResponseIdle(reserving: eventId)
        // An interjection that was given up on while it waited its turn must not speak after all.
        if Task.isCancelled {
            withdraw(eventId)
            throw CancellationError()
        }
        try await send(ResponseCreate(event_id: eventId, response: .init(instructions: instructions)), as: eventId)
    }

    /// Returns once no response is in progress, or after `timeout`, with the turn held for the request `eventId`.
    ///
    /// The server refuses a second response but lets an out-of-band one overlap the conversation's, so turns go
    /// out one at a time: the next waiter is released once this request has been created or refused.
    func waitUntilResponseIdle(reserving eventId: String, timeout: Duration = .seconds(15)) async {
        guard !isResponseIdle else {
            pendingResponseRequests.append(eventId)
            return
        }
        let waiterId = UUID()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.waitForIdle(as: waiterId, reserving: eventId) }
            group.addTask {
                // Ends the wait when time runs out or the caller is cancelled; after a release it does nothing.
                try? await Task.sleep(for: timeout)
                await self.release(waiterId)
            }
            await group.next()
            group.cancelAll()
        }
    }

    /// Settles the oldest request: the server echoes a client's event id only when it refuses one.
    func responseCreated(id: String?) {
        if !pendingResponseRequests.isEmpty {
            pendingResponseRequests.removeFirst()
        }
        if let id {
            activeResponses.insert(id)
        }
    }

    func responseFinished(id: String?) {
        if let id {
            activeResponses.remove(id)
        }
        releaseIdleWaitersIfIdle()
    }

    /// Gives up the turn a request held, because it was refused, cancelled, or never sent.
    func withdraw(_ eventId: String) {
        pendingResponseRequests.removeAll { $0 == eventId }
        releaseIdleWaitersIfIdle()
    }

    /// Hands the turn to the waiter that has been waiting longest, if there is a turn to hand out.
    func releaseIdleWaitersIfIdle() {
        guard isResponseIdle, !idleWaiters.isEmpty else {
            return
        }
        release(idleWaiters.removeFirst())
    }

    func resetResponseTracking() {
        activeResponses.removeAll()
        pendingResponseRequests.removeAll()
        for waiter in idleWaiters {
            waiter.continuation.resume()
        }
        idleWaiters.removeAll()
    }

    /// Sends a request that holds the turn; if it never leaves the client, the turn goes to the next waiter.
    private func send(_ message: some Encodable, as eventId: String) async throws {
        do {
            try await sendMessage(message)
        } catch {
            withdraw(eventId)
            throw error
        }
    }

    private func waitForIdle(as waiterId: UUID, reserving eventId: String) async {
        await withCheckedContinuation { continuation in
            if isResponseIdle {
                pendingResponseRequests.append(eventId)
                continuation.resume()
            } else {
                idleWaiters.append(IdleWaiter(id: waiterId, eventId: eventId, continuation: continuation))
            }
        }
    }

    private func release(_ waiterId: UUID) {
        guard let index = idleWaiters.firstIndex(where: { $0.id == waiterId }) else {
            return
        }
        release(idleWaiters.remove(at: index))
    }

    private func release(_ waiter: IdleWaiter) {
        pendingResponseRequests.append(waiter.eventId)
        waiter.continuation.resume()
    }
}
