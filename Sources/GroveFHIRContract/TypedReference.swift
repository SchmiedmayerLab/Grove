//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
public import ModelsR4


/// Stable identity used to detect exact duplicate logical references.
public enum TypedReferenceIdentity: Hashable, Sendable {
    case identifier(type: ResourceType, identifier: BusinessIdentifier)
}


/// A fail-closed typed-reference validation failure.
public enum TypedReferenceError: Error, Equatable, Sendable {
    /// The reference is empty, ambiguous, malformed, or targets another resource type.
    case invalidReference(expectedResourceType: ResourceType)
    /// Conversion-context literals cannot resolve because callers do not supply Bundle entries.
    case literalRequiresBundleEntry(String)
}


/// Shared logical Reference rules for Grove conversion contexts.
public enum TypedReference {
    /// The exact refusal every producer reports for a literal in a conversion context.
    public static func literalRefusal(field: String) -> String {
        "\(field) must use an identifier-only logical Reference; literals require a Bundle entry"
    }

    /// Accepts a complete Identifier plus an exact resource-type token in `Reference.type`.
    ///
    /// Conversion contexts do not carry the referenced Patient or ResearchStudy resource, so a
    /// literal cannot satisfy the exchange Bundle's closed-reference rule. Graph assemblers mint
    /// internal literals only after their target entry and deterministic fullUrl both exist.
    public static func validate(
        _ reference: Reference,
        expectedResourceType: ResourceType
    ) throws(TypedReferenceError) -> TypedReferenceIdentity {
        let literal = reference.reference?.value?.string
        let identifier = reference.identifier
        guard literal == nil || identifier == nil else {
            throw TypedReferenceError.invalidReference(
                expectedResourceType: expectedResourceType
            )
        }
        if let literal {
            throw TypedReferenceError.literalRequiresBundleEntry(literal)
        }
        guard reference.reference == nil,
              let identifier else {
            throw TypedReferenceError.invalidReference(
                expectedResourceType: expectedResourceType
            )
        }

        let declaredType = reference.type?.value?.url.absoluteString
        guard declaredType == expectedResourceType.rawValue else {
            throw TypedReferenceError.invalidReference(
                expectedResourceType: expectedResourceType
            )
        }

        guard let businessIdentifier = try? BusinessIdentifier(identifier) else {
            throw TypedReferenceError.invalidReference(
                expectedResourceType: expectedResourceType
            )
        }
        return .identifier(type: expectedResourceType, identifier: businessIdentifier)
    }
}
