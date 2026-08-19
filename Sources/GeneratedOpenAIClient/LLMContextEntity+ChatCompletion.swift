//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFoundation
import GroveLLM


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMContextEntity.Role {
    /// Maps the `LLMContextEntity/Role` to the OpenAI chat completion role.
    package var openAIRepresentation: Components.Schemas.ChatCompletionRole {
        switch self {
        case .assistant, .toolCalls, .assistantThinking: .assistant
        case .user: .user
        case .system: .system
        case .toolCallResponse: .tool
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMContextEntity {
    private static let logger = Logger(subsystem: "org.grovealliance", category: "GeneratedOpenAIClient")

    /// The entity's representation as a Chat Completions request message, if it has one.
    ///
    /// Shared by every OpenAI-compatible platform — OpenAI itself, and any fog node speaking the same API.
    package func toChatMessage() -> Components.Schemas.ChatCompletionRequestMessage? {
        switch role {
        case let .toolCallResponse(id: functionID, name: _):
            .ChatCompletionRequestToolMessage(.init(
                role: .tool,
                content: .case1(content),
                tool_call_id: functionID
            ))
        case .assistant:
            .ChatCompletionRequestAssistantMessage(.init(
                content: .case1(content),
                role: .assistant
            ))
        case .toolCalls(let toolCalls):
            .ChatCompletionRequestAssistantMessage(.init(
                role: .assistant,
                tool_calls: toolCalls.map { toolCall in
                    .ChatCompletionMessageToolCall(.init(
                        id: toolCall.id,
                        _type: .function,
                        function: .init(name: toolCall.name, arguments: toolCall.arguments)
                    ))
                }
            ))
        case .system:
            systemMessage()
        case .user:
            userMessage()
        case .assistantThinking:
            // Reasoning summaries are local UI artifacts; the Chat Completions API has no input slot for them.
            nil
        }
    }

    private func systemMessage() -> Components.Schemas.ChatCompletionRequestMessage? {
        guard let role = Components.Schemas.ChatCompletionRequestSystemMessage
            .rolePayload(rawValue: role.openAIRepresentation.rawValue) else {
            Self.logger.error("Could not create ChatCompletionRequestSystemMessage payload")
            return nil
        }
        return .ChatCompletionRequestSystemMessage(.init(content: .case1(content), role: role))
    }

    private func userMessage() -> Components.Schemas.ChatCompletionRequestMessage {
        guard let imageContent = _imageContent else {
            return .ChatCompletionRequestUserMessage(.init(content: .case1(content), role: .user))
        }
        return .ChatCompletionRequestUserMessage(.init(
            content: .case2([
                .ChatCompletionRequestMessageContentPartImage(.init(
                    _type: .image_url,
                    image_url: .init(
                        url: "data:\(imageContent.contentType);base64,\(imageContent.base64Image)",
                        detail: .auto
                    )
                ))
            ]),
            role: .user
        ))
    }
}
