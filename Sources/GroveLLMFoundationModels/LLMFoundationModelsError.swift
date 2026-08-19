//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import FoundationModels
public import GroveLLM


/// Errors that can occur while running an Apple `FoundationModels` LLM.
@available(iOS 27, macOS 27, visionOS 27, *)
public enum LLMFoundationModelsError: LLMError {
    /// The device is not eligible for the requested model.
    case deviceNotEligible
    /// Apple Intelligence has not been turned on.
    case appleIntelligenceNotEnabled
    /// The model is eligible but not yet ready — assets are still downloading, or the system is busy.
    case modelNotReady
    /// The prompt or the response tripped the model's safety guardrails.
    case guardrailViolation
    /// The conversation no longer fits into the model's context window.
    case contextSizeExceeded
    /// The model declined to answer in the requested language.
    case unsupportedLanguageOrLocale
    /// Too many requests were made in too short a time.
    case rateLimited
    /// Generation failed for a reason the adapter does not model separately.
    case generationFailed(String)


    public var errorDescription: String? {
        switch self {
        case .deviceNotEligible:
            String(localized: "LLM_FM_DEVICE_NOT_ELIGIBLE_DESCRIPTION", bundle: .module)
        case .appleIntelligenceNotEnabled:
            String(localized: "LLM_FM_APPLE_INTELLIGENCE_OFF_DESCRIPTION", bundle: .module)
        case .modelNotReady:
            String(localized: "LLM_FM_MODEL_NOT_READY_DESCRIPTION", bundle: .module)
        case .guardrailViolation:
            String(localized: "LLM_FM_GUARDRAIL_DESCRIPTION", bundle: .module)
        case .contextSizeExceeded:
            String(localized: "LLM_FM_CONTEXT_SIZE_DESCRIPTION", bundle: .module)
        case .unsupportedLanguageOrLocale:
            String(localized: "LLM_FM_UNSUPPORTED_LANGUAGE_DESCRIPTION", bundle: .module)
        case .rateLimited:
            String(localized: "LLM_FM_RATE_LIMITED_DESCRIPTION", bundle: .module)
        case .generationFailed:
            String(localized: "LLM_FM_GENERATION_FAILED_DESCRIPTION", bundle: .module)
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .deviceNotEligible:
            String(localized: "LLM_FM_DEVICE_NOT_ELIGIBLE_RECOVERY", bundle: .module)
        case .appleIntelligenceNotEnabled:
            String(localized: "LLM_FM_APPLE_INTELLIGENCE_OFF_RECOVERY", bundle: .module)
        case .modelNotReady:
            String(localized: "LLM_FM_MODEL_NOT_READY_RECOVERY", bundle: .module)
        case .guardrailViolation:
            String(localized: "LLM_FM_GUARDRAIL_RECOVERY", bundle: .module)
        case .contextSizeExceeded:
            String(localized: "LLM_FM_CONTEXT_SIZE_RECOVERY", bundle: .module)
        case .unsupportedLanguageOrLocale:
            String(localized: "LLM_FM_UNSUPPORTED_LANGUAGE_RECOVERY", bundle: .module)
        case .rateLimited:
            String(localized: "LLM_FM_RATE_LIMITED_RECOVERY", bundle: .module)
        case .generationFailed:
            String(localized: "LLM_FM_GENERATION_FAILED_RECOVERY", bundle: .module)
        }
    }

    public var failureReason: String? {
        switch self {
        case .generationFailed(let reason): reason
        default: nil
        }
    }


    /// Maps what `FoundationModels` throws onto the cases this adapter reports.
    init(_ error: any Error) {
        #if compiler(>=6.4)
        self = Self.mapLanguageModelError(error)
        #else
        self = Self.mapGenerationError(error)
        #endif
    }

    #if compiler(>=6.4)
    private static func mapLanguageModelError(_ error: any Error) -> Self {
        guard let error = error as? LanguageModelError else {
            return .generationFailed(error.localizedDescription)
        }
        return switch error {
        case .contextSizeExceeded: Self.contextSizeExceeded
        case .rateLimited: Self.rateLimited
        case .guardrailViolation, .refusal: Self.guardrailViolation
        case .unsupportedLanguageOrLocale: Self.unsupportedLanguageOrLocale
        default: Self.generationFailed(error.localizedDescription)
        }
    }
    #else
    private static func mapGenerationError(_ error: any Error) -> Self {
        guard let error = error as? LanguageModelSession.GenerationError else {
            return .generationFailed(error.localizedDescription)
        }
        return switch error {
        case .exceededContextWindowSize: Self.contextSizeExceeded
        case .rateLimited: Self.rateLimited
        case .guardrailViolation, .refusal: Self.guardrailViolation
        case .unsupportedLanguageOrLocale: Self.unsupportedLanguageOrLocale
        default: Self.generationFailed(error.localizedDescription)
        }
    }
    #endif
}
