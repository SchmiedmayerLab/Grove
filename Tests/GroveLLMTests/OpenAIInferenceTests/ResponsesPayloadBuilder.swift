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


/// Builds the body of a non-streamed `POST /v1/responses` reply.
///
/// The envelope is a trimmed copy of a real response, so what the fallback path parses here is the shape a server
/// actually sends rather than one inferred from the schema.
struct ResponsesPayloadBuilder {
    private var output: [[String: Any]] = []

    /// A web citation, as the API annotates a span of output text with one.
    static func urlCitation(
        url: String,
        title: String,
        startIndex: Int = 0,
        endIndex: Int = 1
    ) -> [String: Any] {
        [
            "type": "url_citation",
            "url": url,
            "title": title,
            "start_index": startIndex,
            "end_index": endIndex
        ]
    }

    /// An assistant message carrying the given text, and any citations that annotate it.
    mutating func message(_ text: String, citations: [[String: Any]] = []) {
        output.append([
            "id": "msg_mock",
            "type": "message",
            "status": "completed",
            "role": "assistant",
            "content": [["type": "output_text", "annotations": citations, "logprobs": [], "text": text]]
        ])
    }

    /// A refusal, which the API models as message content rather than as its own item type.
    mutating func refusal(_ text: String) {
        output.append([
            "id": "msg_mock_refusal",
            "type": "message",
            "status": "completed",
            "role": "assistant",
            "content": [["type": "refusal", "refusal": text]]
        ])
    }

    /// A reasoning item with a single summary part.
    mutating func reasoning(summary: String) {
        output.append([
            "id": "rs_mock",
            "type": "reasoning",
            "summary": [["type": "summary_text", "text": summary]]
        ])
    }

    /// A function call the model requested.
    mutating func functionCall(name: String, arguments: String, callId: String = "call_mock") {
        output.append([
            "id": "fc_mock",
            "type": "function_call",
            "call_id": callId,
            "name": name,
            "arguments": arguments
        ])
    }

    /// The decoded response, ready to hand back from a mocked client.
    ///
    /// The envelope carries every field a real reply does — including the ones the server sends as `null` — because
    /// the generated schema makes them required, and a fixture that omits them would fail to decode for a reason
    /// that has nothing to do with what the test is checking.
    func response(id: String = "resp_mock") throws -> Components.Schemas.Response {
        let envelope: [String: Any] = [
            "id": id,
            "object": "response",
            "created_at": 1_786_764_904,
            "completed_at": 1_786_764_904,
            "status": "completed",
            "model": "gpt-5.4",
            "output": output,
            "metadata": [:],
            "parallel_tool_calls": true,
            "temperature": 1.0,
            "top_p": 1.0,
            "tool_choice": "auto",
            "tools": [],
            "text": ["format": ["type": "text"]],
            "truncation": "disabled",
            "usage": [
                "input_tokens": 11,
                "input_tokens_details": ["cached_tokens": 0],
                "output_tokens": 5,
                "output_tokens_details": ["reasoning_tokens": 0],
                "total_tokens": 16
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope)
        return try JSONDecoder().decode(Components.Schemas.Response.self, from: data)
    }

    /// The decoded response, wrapped as a successful non-streamed API output.
    func output(id: String = "resp_mock") throws -> Operations.createResponse.Output {
        .ok(.init(body: .json(try response(id: id))))
    }
}
