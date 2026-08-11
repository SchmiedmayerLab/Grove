//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// Defines universally occurring `Error`s while handling LLMs with GroveLLM.
@available(iOS 18, macOS 15, watchOS 11, *)
public enum LLMDefaultError: LLMError {
    /// Indicates an unknown error during LLM execution.
    case unknown(any Error)
    
    
    public var errorDescription: String? {
        switch self {
        case .unknown:
            String(localized: LocalizedStringResource("LLM_UNKNOWN_ERROR_DESCRIPTION", bundle: .atURL(from: .module)))
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .unknown:
            String(localized: LocalizedStringResource("LLM_UNKNOWN_ERROR_RECOVERY_SUGGESTION", bundle: .atURL(from: .module)))
        }
    }

    public var failureReason: String? {
        switch self {
        case .unknown:
            String(localized: LocalizedStringResource("LLM_UNKNOWN_ERROR_FAILURE_REASON", bundle: .atURL(from: .module)))
        }
    }
    
    
    public static func == (lhs: LLMDefaultError, rhs: LLMDefaultError) -> Bool {
        switch (lhs, rhs) {
        case (.unknown, .unknown): true
        }
    }
}


/// Defines a common `Error` protocol which should be used for defining errors within the GroveLLM ecosystem.
///
/// An example conformance to the ``LLMError`` can be found in the `GroveLLMLocal` target.
///
/// ```swift
/// public enum LLMLocalError: LLMError {
///     case modelNotFound
///
///     public var errorDescription: String? { "Some example error description" }
///     public var recoverySuggestion: String? { "Some example recovery suggestion" }
///     public var failureReason: String? { "Some example failure reason" }
/// }
/// ```
public protocol LLMError: LocalizedError, Equatable {}      // `LocalizedError` conforms to `Sendable`
