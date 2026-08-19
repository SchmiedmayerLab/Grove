//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GeneratedOpenAIClient


@available(iOS 18, macOS 15, watchOS 11, *)
internal protocol LLMOpenAIChatClientProtocol: Sendable {
    func createChatCompletion(_ input: Operations.createChatCompletion.Input) async throws -> Operations.createChatCompletion.Output
    
    func retrieveModel(_ input: Operations.retrieveModel.Input) async throws -> Operations.retrieveModel.Output
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension Client: LLMOpenAIChatClientProtocol {}
