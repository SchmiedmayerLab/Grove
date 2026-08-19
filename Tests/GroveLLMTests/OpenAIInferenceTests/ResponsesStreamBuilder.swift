//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GeneratedOpenAIClient
import OpenAPIRuntime


/// Builds the server-sent event stream that the OpenAI Responses API emits, for use as a mocked API response.
///
/// The events are written as raw JSON rather than through the generated types, mirroring how the session parses them:
/// it reads the SSE payloads untyped, because the event union is far wider than the handful of events we act on.
struct ResponsesStreamBuilder {
    private var events: [String] = []

    /// `response.created`, which opens every response.
    mutating func created() {
        append(["type": "response.created", "response": ["id": "resp_mock", "status": "in_progress"]])
    }

    /// A chunk of assistant output text.
    mutating func outputTextDelta(_ delta: String) {
        append(["type": "response.output_text.delta", "delta": delta])
    }

    /// Marks the assistant's text output as finished.
    mutating func outputTextDone() {
        append(["type": "response.output_text.done"])
    }

    /// Opens a new reasoning summary part.
    mutating func reasoningSummaryPartAdded() {
        append(["type": "response.reasoning_summary_part.added"])
    }

    /// A chunk of the model's reasoning summary.
    mutating func reasoningSummaryDelta(_ delta: String) {
        append(["type": "response.reasoning_summary_text.delta", "delta": delta])
    }

    /// Closes the current reasoning summary part.
    mutating func reasoningSummaryPartDone() {
        append(["type": "response.reasoning_summary_part.done"])
    }

    /// A finalized `function_call` output item, which is where the session picks tool calls up.
    mutating func functionCall(name: String, arguments: String, callId: String = "call_mock") {
        append([
            "type": "response.output_item.done",
            "item": ["type": "function_call", "call_id": callId, "name": name, "arguments": arguments]
        ])
    }

    /// An output item that is not a function call, which the session must ignore.
    mutating func messageOutputItemDone() {
        append(["type": "response.output_item.done", "item": ["type": "message", "role": "assistant"]])
    }

    /// `response.completed`, carrying the response id used for multi-turn continuation.
    mutating func completed(responseId: String = "resp_mock") {
        append(["type": "response.completed", "response": ["id": responseId, "status": "completed"]])
    }

    /// `response.failed`, carrying an error message.
    mutating func failed(message: String) {
        append(["type": "response.failed", "response": ["error": ["message": message]]])
    }

    /// `response.incomplete`, the truncated-but-continuable end state.
    mutating func incomplete(responseId: String = "resp_incomplete") {
        append(["type": "response.incomplete", "response": ["id": responseId, "status": "incomplete"]])
    }

    /// A chunk of refusal text.
    mutating func refusalDelta(_ delta: String) {
        append(["type": "response.refusal.delta", "delta": delta])
    }

    /// Marks the refusal as finished.
    mutating func refusalDone() {
        append(["type": "response.refusal.done"])
    }

    /// A top-level in-stream `error` event.
    mutating func errorEvent(message: String) {
        append(["type": "error", "message": message])
    }

    /// An event the session does not handle, which must not disturb the stream.
    mutating func unknownEvent() {
        append(["type": "response.some_future_event_we_do_not_know_about"])
    }

    /// A payload that isn't valid JSON, which must not disturb the stream.
    mutating func malformedEvent() {
        events.append("data: {not json\n\n")
    }

    /// The built events as an `Operations.createResponse.Output`, ready to hand back from the mocked client.
    func output() -> Operations.createResponse.Output {
        let stream = AsyncStream<String> { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
        return .ok(.init(body: .text_event_hyphen_stream(HTTPBody(stream, length: .unknown))))
    }

    private mutating func append(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            preconditionFailure("Unable to encode the mocked event payload: \(payload)")
        }
        events.append("data: \(json)\n\n")
    }
}
