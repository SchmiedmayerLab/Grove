//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GeneratedOpenAIClient
import GroveLLMOpenAI


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMOpenAIRealtimeSession {
    struct ToolTask {
        let generationId: String?
        let task: Task<Void, Never>
    }

    /// Submit every tool result before requesting one continuation of the same logical generation.
    @MainActor
    static func continueToolResponse(
        _ response: LLMRealtimeAudioEvent.Response,
        execute: (LLMOpenAIStreamResult.FunctionCall) async throws -> ToolCallLLMSessionTypes.ToolCallResponse,
        sendOutput: (ToolCallLLMSessionTypes.ToolCallResponse) async throws -> Void,
        requestNext: (String?) async throws -> Void
    ) async throws {
        for call in response.functionCalls {
            try Task.checkCancellation()
            let output = try await execute(call)
            try Task.checkCancellation()
            try await sendOutput(output)
        }
        try Task.checkCancellation()
        try await requestNext(response.generationId)
    }

    @MainActor
    func registerGeneration(_ id: String) {
        activeGenerations.insert(id)
    }

    @MainActor
    func finishGeneration(_ id: String) {
        activeGenerations.remove(id)
        for (responseId, tool) in toolTasks where tool.generationId == id {
            tool.task.cancel()
            toolTasks.removeValue(forKey: responseId)
        }
        settleToolState()
    }

    @MainActor
    func stopEventHandling() {
        eventHandlingId = UUID()
        eventTask?.cancel()
        eventTask = nil
        for tool in toolTasks.values {
            tool.task.cancel()
        }
        toolTasks.removeAll()
        activeGenerations.removeAll()
        assistantTranscripts.reset(context: &context)
        transcripts = UserTranscriptTracker()
    }

    @MainActor
    func startToolContinuation(
        _ response: LLMRealtimeAudioEvent.Response,
        connectionId: UUID,
        broadcaster: EventBroadcaster<LLMRealtimeAudioEvent>
    ) {
        guard toolTasks[response.id] == nil,
              response.generationId.map(activeGenerations.contains) ?? true else {
            return
        }
        let handlingId = eventHandlingId
        let task = Task {
            defer {
                if handlingId == eventHandlingId {
                    toolTasks.removeValue(forKey: response.id)
                    settleToolState()
                }
            }
            do {
                try checkToolContinuation(response, handlingId: handlingId)
                if let gracePeriod = schema.parameters.transcriptGracePeriod {
                    await transcripts.waitUntilSettled(timeout: gracePeriod)
                }
                try checkToolContinuation(response, handlingId: handlingId)
                try await performToolContinuation(response, handlingId: handlingId, connectionId: connectionId)
            } catch {
                guard handlingId == eventHandlingId else {
                    return
                }
                if let generationId = response.generationId {
                    await broadcaster.broadcast(.generationFailed(generationId: generationId, error: error))
                } else if !Task.isCancelled {
                    Self.logger.error("GroveLLMOpenAIRealtime: Tool continuation failed: \(error)")
                }
            }
        }
        toolTasks[response.id] = ToolTask(generationId: response.generationId, task: task)
        state = .callingTools
    }

    @MainActor
    private func settleToolState() {
        if toolTasks.isEmpty, case .callingTools = state {
            state = .ready
        }
    }

    @MainActor
    private func checkToolContinuation(_ response: LLMRealtimeAudioEvent.Response, handlingId: UUID) throws {
        try Task.checkCancellation()
        guard handlingId == eventHandlingId, response.generationId.map(activeGenerations.contains) ?? true else {
            throw CancellationError()
        }
    }

    @MainActor
    private func performToolContinuation(_ response: LLMRealtimeAudioEvent.Response, handlingId: UUID, connectionId: UUID) async throws {
        try await Self.continueToolResponse(
            response,
            execute: { call in
                try self.checkToolContinuation(response, handlingId: handlingId)
                return try await self.callFunction(
                    availableFunctions: self.schema.functions,
                    functionCallArgs: call,
                    failureHandling: .returnErrorInResponse
                )
            },
            sendOutput: { output in
                try self.checkToolContinuation(response, handlingId: handlingId)
                try await self.sendToolOutput(output, generationId: response.generationId, connectionId: connectionId)
            },
            requestNext: { generationId in
                try self.checkToolContinuation(response, handlingId: handlingId)
                try await self.apiConnection.requestResponse(
                    toolChoice: self.schema.parameters.followUpToolChoice, generationId: generationId, connectionId: connectionId
                )
            }
        )
    }

    private func sendToolOutput(
        _ output: ToolCallLLMSessionTypes.ToolCallResponse,
        generationId: String?,
        connectionId: UUID
    ) async throws {
        typealias ConversationItemCreate = Components.Schemas.RealtimeClientEventConversationItemCreate
        let eventId = UUID().uuidString
        let event = ConversationItemCreate(
            event_id: eventId,
            _type: .conversation_period_item_period_create,
            item: .init(value5: .init(_type: .function_call_output, call_id: output.functionID, output: output.response))
        )
        try await apiConnection.sendMessage(event, eventId: eventId, generationId: generationId, connectionId: connectionId)
    }
}
