//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveLLM
@testable import GroveLLMOpenAI
import Testing


/// Covers which failures are worth offering the user another attempt at.
///
/// The chat shows a retry only for the failures that could go the other way. Getting this wrong is quiet in both
/// directions: a retry on a rejected key is a button that can never work, and no retry on a dropped connection
/// strands a conversation that one tap would have resumed.
@Suite("LLM Error Retriability")
struct LLMErrorRetryTests {
    @Test("A failure of the transport or of the moment can be retried", arguments: [
        LLMOpenAIError.connectivityIssues(URLError(.timedOut)),
        LLMOpenAIError.generationError,
        LLMOpenAIError.toolCallError(URLError(.timedOut))
    ])
    func transientFailuresAreRetriable(error: LLMOpenAIError) {
        #expect(error.isRetriable)
    }

    @Test("A credential, a quota, or a request the API refused cannot be retried past", arguments: [
        LLMOpenAIError.invalidAPIToken,
        LLMOpenAIError.missingAPITokenInKeychain,
        LLMOpenAIError.insufficientQuota,
        LLMOpenAIError.invalidRequest,
        LLMOpenAIError.fileAttachmentsRequireResponsesAPI,
        LLMOpenAIError.storageError,
        LLMOpenAIError.modelAccessError(URLError(.badURL)),
        LLMOpenAIError.invalidToolCallName,
        LLMOpenAIError.invalidToolCallArguments(URLError(.badURL)),
        LLMOpenAIError.toolCallSchemaExtractionError(URLError(.badURL))
    ])
    func permanentFailuresAreNotRetriable(error: LLMOpenAIError) {
        #expect(!error.isRetriable)
    }

    @Test("An error that says nothing about itself is treated as worth another try")
    func theDefaultIsRetriable() {
        #expect(LLMDefaultError.unknown(URLError(.timedOut)).isRetriable, "a transient failure is the common case")
    }
}
