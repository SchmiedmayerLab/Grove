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
    // `Regex` needs iOS 16/macOS 13, above the package deployment floor, so the invariant's own
    // pattern is kept verbatim and matched with NSRegularExpression instead.
    /// Semantic Versioning 2.0.0, matching the `qg-version-1` IG invariant.
    public static func isSemanticVersion(_ value: String) -> Bool {
        guard let semanticVersion = try? NSRegularExpression(
            // swiftlint:disable:next line_length
            pattern: #"^(0|[1-9][0-9]*)[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)([.](0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*))?([+]([0-9A-Za-z-]+)([.][0-9A-Za-z-]+)*)?$"#
        ) else {
            return false
        }
        let range = NSRange(value.startIndex..., in: value)
        return semanticVersion.firstMatch(in: value, options: [.anchored], range: range)?.range == range
    }
}
