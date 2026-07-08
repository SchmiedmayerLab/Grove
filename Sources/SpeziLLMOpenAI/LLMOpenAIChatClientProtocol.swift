//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GeneratedOpenAIClient


@available(iOS 17, macOS 14, visionOS 1, *)
internal protocol LLMOpenAIChatClientProtocol {
    func createChatCompletion(_ input: Operations.createChatCompletion.Input) async throws -> Operations.createChatCompletion.Output
    
    func retrieveModel(_ input: Operations.retrieveModel.Input) async throws -> Operations.retrieveModel.Output
}

@available(iOS 17, macOS 14, visionOS 1, *)
extension Client: LLMOpenAIChatClientProtocol {}
