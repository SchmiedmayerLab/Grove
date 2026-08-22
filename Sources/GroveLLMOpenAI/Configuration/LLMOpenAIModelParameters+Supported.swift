//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMOpenAIModelParameters {
    /// The same parameters, without the sampling controls the given model refuses.
    ///
    /// Sending one to a model that has moved past them fails the request outright, which would turn a parameter a
    /// caller set once into an app whose every answer errors. Dropping them costs the caller the control it asked
    /// for and nothing else, so a release keeps answering; a debug build traps instead, because the call site is
    /// where this is worth fixing.
    func accepted(by modelType: some LLMOpenAILikePlatformModelType) -> Self {
        guard !modelType.supportsSamplingControls else {
            return self
        }
        let requested = [temperature, topP, presencePenalty, frequencyPenalty].contains { $0 != nil }
        guard requested || !logitBias.additionalProperties.isEmpty else {
            return self
        }
        assertionFailure(
            """
            \(modelType.rawValue) does not accept sampling controls; remove them from the schema's `modelParameters`.
            """
        )
        return Self(
            responseFormat: responseFormat,
            responsesTextFormat: responsesTextFormat,
            temperature: nil,
            topP: nil,
            completionsPerOutput: completionsPerOutput,
            stopSequence: stopSequence,
            maxOutputLength: maxOutputLength,
            presencePenalty: nil,
            frequencyPenalty: nil,
            logitBias: .init()
        )
    }
}
