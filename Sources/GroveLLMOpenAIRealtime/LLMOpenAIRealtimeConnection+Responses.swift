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

    /// Registers request ownership before sending so an immediate refusal reaches the correct generation.
    func sendMessage(
        _ object: some Encodable,
        eventId: String,
        generationId: String?,
        connectionId expectedConnectionId: UUID? = nil
    ) async throws {
        let expectedConnectionId = expectedConnectionId ?? connectionId
        try checkConnection(expectedConnectionId)
        if let generationId {
            await eventStream.broadcast(.generationEventSent(generationId: generationId, eventId: eventId))
        }
        try checkConnection(expectedConnectionId)
        try await sendMessage(object)
    }

    /// Work from a previous connection must not submit tool results after a reconnect.
    func checkConnection(_ expectedConnectionId: UUID?) throws {
        try Task.checkCancellation()
        if let expectedConnectionId, connectionId != expectedConnectionId {
            throw CancellationError()
        }
    }

    /// Requests the model's next response, optionally without letting it call tools.
    func requestResponse(
        toolChoice: LLMOpenAIRealtimeParameters.FollowUpToolChoice = .auto,
        eventId: String = UUID().uuidString,
        generationId: String? = nil,
        connectionId expectedConnectionId: UUID? = nil
    ) async throws {
        struct ResponseCreate: Encodable {
            struct Response: Encodable {
                // swiftlint:disable:next identifier_name
                let tool_choice: String?
                let metadata: [String: String]
            }

            let type = "response.create"
            // swiftlint:disable:next identifier_name
            let event_id: String
            let response: Response
        }
        let expectedConnectionId = expectedConnectionId ?? connectionId
        try checkConnection(expectedConnectionId)
        let request = LLMRealtimeAudioEvent.ResponseRequest(eventId: eventId, generationId: generationId)
        await waitUntilResponseIdle(reserving: eventId)
        do {
            try checkConnection(expectedConnectionId)
        } catch {
            withdraw(eventId)
            throw error
        }
        try await send(
            ResponseCreate(
                event_id: eventId,
                response: .init(tool_choice: toolChoice == .auto ? nil : toolChoice.rawValue, metadata: request.metadata)
            ),
            as: request,
            connectionId: expectedConnectionId
        )
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
                let metadata: [String: String]
            }

            let type = "response.create"
            // swiftlint:disable:next identifier_name
            let event_id: String
            let response: Response
        }
        let expectedConnectionId = connectionId
        try checkConnection(expectedConnectionId)
        let eventId = UUID().uuidString
        let request = LLMRealtimeAudioEvent.ResponseRequest(eventId: eventId, generationId: nil)
        await waitUntilResponseIdle(reserving: eventId)
        do {
            try checkConnection(expectedConnectionId)
        } catch {
            withdraw(eventId)
            throw error
        }
        try await send(
            ResponseCreate(event_id: eventId, response: .init(instructions: instructions, metadata: request.metadata)),
            as: request,
            connectionId: expectedConnectionId
        )
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

    /// Settles only the request named in response metadata; VAD responses have no local reservation.
    func responseCreated(id: String?, requestId: String? = nil, generationId: String? = nil) {
        if let requestId {
            pendingResponseRequests.removeAll { $0 == requestId }
        }
        if let id {
            activeResponses.insert(id)
            if let requestId, responseRequests[id] == nil {
                responseRequests[id] = .init(eventId: requestId, generationId: generationId)
            }
        }
    }

    func responseFinished(id: String?) {
        if let id {
            activeResponses.remove(id)
            responseRequests.removeValue(forKey: id)
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
        connectionId = UUID()
        activeResponses.removeAll()
        responseRequests.removeAll()
        pendingResponseRequests.removeAll()
        for waiter in idleWaiters {
            waiter.continuation.resume()
        }
        idleWaiters.removeAll()
    }

    /// Sends a request that holds the turn; if it never leaves the client, the turn goes to the next waiter.
    private func send(
        _ message: some Encodable,
        as request: LLMRealtimeAudioEvent.ResponseRequest,
        connectionId expectedConnectionId: UUID? = nil
    ) async throws {
        do {
            try checkConnection(expectedConnectionId)
            await eventStream.broadcast(.responseRequested(request))
            try checkConnection(expectedConnectionId)
            try await sendMessage(message, eventId: request.eventId, generationId: request.generationId, connectionId: expectedConnectionId)
        } catch {
            withdraw(request.eventId)
            throw error
        }
    }

    private func waitForIdle(as waiterId: UUID, reserving eventId: String) async {
        await withCheckedContinuation { continuation in
            guard !Task.isCancelled else {
                continuation.resume()
                return
            }
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
