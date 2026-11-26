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


/// Tracks the provider's terminal marker and usage across one Chat Completions response.
@available(iOS 18, macOS 15, watchOS 11, *)
struct OpenAIChatStream {
    private let decoder = JSONDecoder()
    private var receivedDone = false
    private(set) var incomplete = false

    mutating func consume(
        _ data: String,
        for generation: OpenAIGeneration
    ) throws -> Components.Schemas.CreateChatCompletionStreamResponse? {
        if data == "[DONE]" {
            receivedDone = true
            return nil
        }
        let chunk = try decoder.decode(Components.Schemas.CreateChatCompletionStreamResponse.self, from: Data(data.utf8))
        generation.observe(id: chunk.id, model: chunk.model, input: chunk.usage?.prompt_tokens, output: chunk.usage?.completion_tokens)
        for choice in chunk.choices {
            if let rawReason = choice.finish_reason?.rawValue, !incomplete {
                let reason = OpenAIGeneration.reason(rawReason)
                generation.observe(id: nil, model: nil, input: nil, output: nil, reason: reason)
                incomplete = reason == .outputLimit || reason == .contentFilter
            }
        }
        return chunk
    }

    func finish(_ generation: OpenAIGeneration) throws {
        guard receivedDone else {
            generation.observe(id: nil, model: nil, input: nil, output: nil, reason: .interrupted)
            throw LLMOpenAIError.generationError
        }
        generation.endRequest(incomplete ? .incomplete : .completed)
    }
}
