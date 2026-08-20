//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// Contract-level failures raised before Grove emits a v0.2 Questionnaire resource or pair.
public enum GroveQuestionnaireFHIRContractError: Error, Equatable, Sendable {
    case missingQuestionnaireURL
    case missingQuestionnaireVersion
    case invalidQuestionnaireVersion(String)
    case emptyQuestionnaire
    case incompleteResponseIdentifier
    case invalidQuestionnaireCanonical(String)
    case invalidPair([GroveQuestionnaireFHIRValidationIssue])
}


/// Shared fixed values and validation helpers for the Grove Questionnaire 0.2 contract.
public enum GroveQuestionnaireFHIRContract {
    /// Semantic Versioning 2.0.0, matching the `qg-version-1` IG invariant.
    public static func isSemanticVersion(_ value: String) -> Bool {
        guard let semanticVersion = try? Regex(
            // swiftlint:disable:next line_length
            #"^(0|[1-9][0-9]*)[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)([.](0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*))?([+]([0-9A-Za-z-]+)([.][0-9A-Za-z-]+)*)?$"#
        ) else {
            return false
        }
        return value.wholeMatch(of: semanticVersion) != nil
    }
}
