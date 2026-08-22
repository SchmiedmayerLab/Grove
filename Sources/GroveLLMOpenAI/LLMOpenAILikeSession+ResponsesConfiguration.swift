//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GeneratedOpenAIClient
import GroveLLM
import OpenAPIRuntime


/// Tracks what the Responses API server already knows about the conversation.
@available(iOS 18, macOS 15, watchOS 11, *)
struct ResponsesConversationState: Sendable {
    /// The ID of the last completed response, used for multi-turn via `previous_response_id`.
    var lastResponseId: String?
    /// How much of the context the server already holds, and therefore need not be re-sent.
    var submittedContextCount = 0
    /// The id of the last entity submitted, used to detect a context that was cleared or rewritten from the outside.
    var submittedContextMarker: UUID?
    /// The submitted-context state of the in-flight request. Committed only once the server confirms the response
    /// completed — a failed request must not mark its input as already delivered.
    var pendingSubmittedContext: (count: Int, marker: UUID)?

    /// Whether the context is still the one the server holds, only extended.
    ///
    /// Comparing the count alone isn't enough: clearing the context and adding a new message leaves it the same length.
    /// The entity that was last submitted must still sit at the position it was submitted from.
    func continuesSubmittedConversation(_ context: LLMContext) -> Bool {
        guard let marker = submittedContextMarker else {
            return submittedContextCount == 0
        }
        guard context.count >= submittedContextCount, submittedContextCount > 0 else {
            return false
        }
        return context[submittedContextCount - 1].id == marker
    }

    /// Confirms that the server accepted and retains the in-flight request's input.
    mutating func commitPendingContext(responseId: String) {
        lastResponseId = responseId
        if let pending = pendingSubmittedContext {
            submittedContextCount = pending.count
            submittedContextMarker = pending.marker
            pendingSubmittedContext = nil
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMOpenAILikeSession {
    /// The input items to send for this request.
    ///
    /// The first request of a session replays the whole context. Once the server holds the conversation — which it does
    /// as soon as we have a `previous_response_id` — only entities produced on our side since then are sent, so that the
    /// model's own output isn't echoed back to it and duplicated.
    private static func responsesInput(
        for context: LLMContext,
        continuing state: ResponsesConversationState
    ) -> [Components.Schemas.InputItem] {
        guard state.lastResponseId != nil else {
            return context.flatMap { $0.toResponsesInputItems() }
        }
        return context
            .dropFirst(state.submittedContextCount)
            .filter { entity in
                switch entity.role {
                case .user, .toolCallResponse:
                    true
                case .system, .assistant, .assistantThinking, .toolCalls:
                    false
                }
            }
            .flatMap { $0.toResponsesInputItems() }
    }

    /// The registered ``LLMTool``s, as Responses API function tools.
    private func responsesTools() throws -> [Components.Schemas.Tool] {
        var tools: [Components.Schemas.Tool] = []
        if schema.searchesTheWeb {
            // The hosted search tool is what produces `url_citation` annotations; without it the model answers
            // from what it already knows and cites nothing.
            tools.append(.web_search(Components.Schemas.WebSearchTool(_type: .web_search)))
        }
        return try tools + schema.functions.values.map { function in
            .function(
                Components.Schemas.FunctionTool(
                    _type: .function,
                    name: function.name,
                    description: function.description,
                    // The schema is already the type the request wants; encoding and re-parsing it only added a
                    // path where a failed cast would have shipped a tool with no parameters at all.
                    parameters: try function.schema.additionalProperties,
                    strict: false
                )
            )
        }
    }

    /// Builds an `Operations.createResponse.Input` for the Responses API.
    ///
    /// - Parameter stream: Whether the server should stream the response back as server-sent events.
    func openAIResponsesQuery(stream: Bool = true) async throws -> Operations.createResponse.Input {
        let context = await context
        let tools = try responsesTools()
        // System messages are hoisted into `instructions`, which is where the Responses API expects them.
        let instructions = context.lazy
            .compactMap { $0.role == .system ? $0.content : nil }
            .joined(separator: "\n\n")
        let reasoning: Components.Schemas.Reasoning? = schema.parameters.modelType.supportsReasoningSummary
            ? .init(summary: .auto)
            : nil
        // Everything handed over becomes server-side state once this response completes; record it as pending
        // and commit it only when `response.completed` confirms the server accepted the input.
        let (input, previousResponseId) = responsesConversation.withLock { state in
            if !state.continuesSubmittedConversation(context) {
                // The context was cleared or rewritten from the outside, so the server's conversation no longer
                // corresponds to it. Start a fresh one from the context as it now stands.
                state = ResponsesConversationState()
            }
            let items = Self.responsesInput(for: context, continuing: state)
            if let marker = context.last?.id {
                state.pendingSubmittedContext = (count: context.count, marker: marker)
            }
            return (items, state.lastResponseId)
        }
        // The API needs something to answer: either new input, or a server-side conversation to continue. Without
        // both it rejects the request with a message that says nothing about the empty context that caused it.
        guard !input.isEmpty || previousResponseId != nil else {
            throw LLMOpenAIError.invalidRequest
        }
        let modelParameters = schema.modelParameters.accepted(by: schema.parameters.modelType)
        return Operations.createResponse.Input(
            body: .json(
                Components.Schemas.CreateResponse(
                    value1: .init(
                        value1: .init(
                            temperature: modelParameters.temperature,
                            top_p: modelParameters.topP
                        ),
                        value2: .init()
                    ),
                    value2: .init(
                        previous_response_id: previousResponseId,
                        model: .init(value1: .init(value1: schema.parameters.modelType.rawValue)),
                        reasoning: reasoning,
                        text: modelParameters.responsesTextFormat.map { .init(format: $0) },
                        tools: tools.isEmpty ? nil : .init(tools)
                    ),
                    value3: .init(
                        input: .case2(input),
                        instructions: instructions.isEmpty ? nil : instructions,
                        stream: stream,
                        max_output_tokens: modelParameters.maxOutputLength
                    )
                )
            )
        )
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMContextEntity {
    /// The entity's representation as Responses API input items.
    ///
    /// Most entities map to at most one item; an entity carrying several parallel tool calls maps to one
    /// `function_call` item each, so that every `function_call_output` in a replayed history finds its call.
    func toResponsesInputItems() -> [Components.Schemas.InputItem] {
        switch role {
        case .system:
            // System messages go into `instructions`, not input items.
            return []
        case .user:
            if let imageContent = _imageContent {
                let image = Components.Schemas.InputImageContent(
                    _type: .input_image,
                    image_url: "data:\(imageContent.contentType);base64,\(imageContent.base64Image)",
                    detail: .auto
                )
                let message = Components.Schemas.InputMessage(_type: .message, role: .user, content: [.InputImageContent(image)])
                return [.Item(.InputMessage(message))]
            }
            if let fileContent = _fileContent {
                let file = Components.Schemas.InputFileContent(
                    _type: .input_file,
                    filename: fileContent.filename,
                    file_data: "data:\(fileContent.contentType);base64,\(fileContent.base64Data)"
                )
                let message = Components.Schemas.InputMessage(_type: .message, role: .user, content: [.InputFileContent(file)])
                return [.Item(.InputMessage(message))]
            }
            return [.EasyInputMessage(.init(role: .user, content: .case1(content)))]
        case .assistant:
            return [.EasyInputMessage(.init(role: .assistant, content: .case1(content)))]
        case .toolCalls(let toolCalls):
            return toolCalls.map { toolCall in
                .Item(.FunctionToolCall(.init(
                    _type: .function_call,
                    call_id: toolCall.id,
                    name: toolCall.name,
                    arguments: toolCall.arguments
                )))
            }
        case .toolCallResponse(id: let functionID, name: _):
            let output = Components.Schemas.FunctionCallOutputItemParam(
                call_id: functionID,
                _type: .function_call_output,
                output: .case1(content)
            )
            return [.Item(.FunctionCallOutputItemParam(output))]
        case .assistantThinking:
            // The server retains its own reasoning state via `previous_response_id`; we don't echo
            // reasoning summaries back as input. They're stored locally for UI display only.
            return []
        }
    }
}
