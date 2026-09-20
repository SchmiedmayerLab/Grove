//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveLLMOpenAI


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMRealtimeAudioEvent {
    package struct ResponseRequest: Sendable {
        let eventId: String
        let generationId: String?

        var metadata: [String: String] {
            var metadata = ["grove_request_id": eventId]
            metadata["grove_generation_id"] = generationId
            return metadata
        }
    }

    package struct Response: Sendable, Decodable {
        enum Status: String, Sendable, Decodable {
            case inProgress = "in_progress"
            case completed
            case cancelled
            case failed
            case incomplete
        }

        private enum CodingKeys: String, CodingKey {
            case id, metadata, status, output
            case statusDetails = "status_details"
        }

        private struct Failure: Decodable {
            let message: String?
        }

        private struct StatusDetails: Decodable {
            let reason: String?
            let error: Failure?
        }

        private enum OutputCodingKeys: String, CodingKey {
            case type, name, arguments
            case callId = "call_id"
        }

        private struct Output: Decodable {
            let functionCall: LLMOpenAIStreamResult.FunctionCall?

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: OutputCodingKeys.self)
                guard try container.decode(String.self, forKey: .type) == "function_call" else {
                    functionCall = nil
                    return
                }
                functionCall = try .init(
                    name: container.decode(String.self, forKey: .name),
                    id: container.decode(String.self, forKey: .callId),
                    arguments: container.decode(String.self, forKey: .arguments)
                )
            }
        }

        let id: String
        let requestId: String?
        let generationId: String?
        let status: Status
        let functionCalls: [LLMOpenAIStreamResult.FunctionCall]
        let failureMessage: String?

        init(
            id: String,
            requestId: String? = nil,
            generationId: String? = nil,
            status: Status,
            functionCalls: [LLMOpenAIStreamResult.FunctionCall] = [],
            failureMessage: String? = nil
        ) {
            self.id = id
            self.requestId = requestId
            self.generationId = generationId
            self.status = status
            self.functionCalls = functionCalls
            self.failureMessage = failureMessage
        }

        package init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            let metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata)
            requestId = metadata?["grove_request_id"]
            generationId = metadata?["grove_generation_id"]
            status = try container.decode(Status.self, forKey: .status)
            functionCalls = try container.decodeIfPresent([Output].self, forKey: .output)?.compactMap(\.functionCall) ?? []
            let details = try container.decodeIfPresent(StatusDetails.self, forKey: .statusDetails)
            failureMessage = details?.error?.message ?? details?.reason
        }
    }

    package struct AssistantTranscriptDelta: Sendable, Decodable {
        private enum CodingKeys: String, CodingKey {
            case delta
            case responseId = "response_id"
            case itemId = "item_id"
            case contentIndex = "content_index"
        }

        let responseId: String
        let itemId: String
        let contentIndex: Int
        let delta: String
    }

    package struct AssistantTranscriptDone: Sendable, Decodable {
        private enum CodingKeys: String, CodingKey {
            case transcript, text
            case responseId = "response_id"
            case itemId = "item_id"
            case contentIndex = "content_index"
        }

        let responseId: String
        let itemId: String
        let contentIndex: Int
        let transcript: String

        init(responseId: String, itemId: String, contentIndex: Int, transcript: String) {
            self.responseId = responseId
            self.itemId = itemId
            self.contentIndex = contentIndex
            self.transcript = transcript
        }

        package init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            responseId = try container.decode(String.self, forKey: .responseId)
            itemId = try container.decode(String.self, forKey: .itemId)
            contentIndex = try container.decode(Int.self, forKey: .contentIndex)
            transcript = try container.decodeIfPresent(String.self, forKey: .transcript)
                ?? container.decode(String.self, forKey: .text)
        }
    }
}
