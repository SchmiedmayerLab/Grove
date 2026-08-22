//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFoundation


/// Contract-level failures raised before Grove emits a Questionnaire resource or pair.
public enum GroveQuestionnaireFHIRContractError: Error, Equatable, Sendable {
    case missingQuestionnaireURL
    case missingQuestionnaireVersion
    case invalidQuestionnaireVersion(String)
    case emptyQuestionnaire
    case incompleteResponseIdentifier
    case invalidQuestionnaireCanonical(String)
    case invalidPair([GroveQuestionnaireFHIRValidationIssue])
}


/// Shared fixed values and validation helpers for the Grove Questionnaire contract.
public enum GroveQuestionnaireFHIRContract {
    /// Semantic Versioning 2.0.0, matching the `qg-version-1` IG invariant.
    public static func isSemanticVersion(_ value: String) -> Bool {
        Version(value) != nil
    }
}
