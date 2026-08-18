//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GeneratedOpenAIClient
import OpenAPIRuntime


/// Helper to process the returned stream by the LLM output generation call, especially in regards to the function call
@available(iOS 18, macOS 15, watchOS 11, *)
package struct LLMOpenAIStreamResult {
    typealias Role = Components.Schemas.ChatCompletionStreamResponseDelta.rolePayload


    package struct FunctionCall {
        var id: String?
        var name: String?
        var arguments: String?
        
        
        package init(name: String? = nil, id: String? = nil, arguments: String? = nil) {
            self.name = name
            self.id = id
            self.arguments = arguments
        }
    }
    
    
    var deltaContent: String?
    var role: Role?
    var functionCall: [FunctionCall]
    var currentFunctionCallIndex = -1


    init(deltaContent: String? = nil, role: Role? = nil, functionCall: [FunctionCall] = []) {
        self.deltaContent = deltaContent
        self.role = role
        self.functionCall = functionCall
    }

    mutating func append(choice: Components.Schemas.CreateChatCompletionStreamResponse.choicesPayloadPayload) -> Self {
        deltaContent = choice.delta.content

        if let role = choice.delta.role {
            self.role = role
        }

        guard let functionCallID = choice.delta.tool_calls?.last?.index else {
            return self
        }

        if functionCallID != currentFunctionCallIndex {
            functionCall.append(FunctionCall())
            currentFunctionCallIndex += 1
        }
        
        var newFunctionCall = functionCall[currentFunctionCallIndex]

        if let functionCallID = choice.delta.tool_calls?.first?.id {
            newFunctionCall.id = (newFunctionCall.id ?? "") + functionCallID
        }

        if let deltaName = choice.delta.tool_calls?.first?.function?.name {
            newFunctionCall.name = (newFunctionCall.name ?? "") + deltaName
        }

        if let deltaArguments = choice.delta.tool_calls?.first?.function?.arguments {
            newFunctionCall.arguments = (newFunctionCall.arguments ?? "") + deltaArguments
        }
        
        // Only assign back if there were changes
        if choice.delta.tool_calls?.first?.id != nil ||
            choice.delta.tool_calls?.first?.function?.name != nil ||
            choice.delta.tool_calls?.first?.function?.arguments != nil {
            functionCall[currentFunctionCallIndex] = newFunctionCall
        }
        
        return self
    }
}
