//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// A present Questionnaire regex constraint is malformed and must not be treated as absent.
public enum QuestionnaireItemRegexError: Error, Equatable, Sendable {
    case repeatedExtension(count: Int)
    case missingValue
    case unsupportedValue
    case invalidPattern(String)

    /// Stable diagnostic text for conversion boundaries that map this error to their own type.
    public var message: String {
        switch self {
        case .repeatedExtension(let count):
            "Expected at most one regex extension, found \(count)"
        case .missingValue:
            "The regex extension is missing its string value"
        case .unsupportedValue:
            "The regex extension value is not a FHIR string"
        case .invalidPattern(let pattern):
            "The regex pattern '\(pattern)' is invalid"
        }
    }
}
