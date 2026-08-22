//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
public import ModelsR4


/// Stable identity used to detect exact duplicate typed references.
public enum GroveFHIRTypedReferenceIdentity: Hashable, Sendable {
    case literal(String)
    case identifier(type: String, identifier: GroveFHIRBusinessIdentifier)
}


/// A fail-closed typed-reference validation failure.
public enum GroveFHIRTypedReferenceError: Error, Equatable, Sendable {
    /// The reference is empty, ambiguous, malformed, or targets another resource type.
    case invalidReference(expectedResourceType: String)
    /// A UUID URN cannot resolve because the referenced resource is not in the emitted graph.
    case unboundBundleUUID(String)
}


/// Shared literal and identifier-only Reference rules for Grove R4 producers.
public enum GroveFHIRTypedReference {
    /// Accepts exactly one of:
    ///
    /// - `ResourceType/FHIR-id`
    /// - an HTTP(S) URL whose path ends exactly in `/ResourceType/FHIR-id`
    /// - a complete Identifier plus an exact `Reference.type`
    ///
    /// Literal references are preserved byte-for-byte. Query, fragment, user information,
    /// history, trailing segments, whitespace, and UUID URNs outside the graph fail closed.
    public static func validate(
        _ reference: Reference,
        expectedResourceType: String
    ) throws -> GroveFHIRTypedReferenceIdentity {
        let literal = reference.reference?.value?.string
        let identifier = reference.identifier
        guard literal == nil || identifier == nil else {
            throw GroveFHIRTypedReferenceError.invalidReference(
                expectedResourceType: expectedResourceType
            )
        }

        let declaredType = reference.type?.value?.url.absoluteString
        let allowedTypes = [
            expectedResourceType,
            "http://hl7.org/fhir/StructureDefinition/\(expectedResourceType)"
        ]
        if let declaredType, !allowedTypes.contains(declaredType) {
            throw GroveFHIRTypedReferenceError.invalidReference(
                expectedResourceType: expectedResourceType
            )
        }

        if let literal {
            if literal.lowercased().hasPrefix("urn:uuid:") {
                throw GroveFHIRTypedReferenceError.unboundBundleUUID(literal)
            }
            guard validLiteral(literal, expectedResourceType: expectedResourceType) else {
                throw GroveFHIRTypedReferenceError.invalidReference(
                    expectedResourceType: expectedResourceType
                )
            }
            return .literal(literal)
        }

        guard let declaredType,
              let identifier,
              let businessIdentifier = try? GroveFHIRBusinessIdentifier(identifier) else {
            throw GroveFHIRTypedReferenceError.invalidReference(
                expectedResourceType: expectedResourceType
            )
        }
        return .identifier(type: declaredType, identifier: businessIdentifier)
    }

    private static func validLiteral(
        _ literal: String,
        expectedResourceType: String
    ) -> Bool {
        guard literal.unicodeScalars.allSatisfy({
            !CharacterSet.whitespacesAndNewlines.contains($0)
                && !CharacterSet.controlCharacters.contains($0)
        }) else {
            return false
        }

        let pathSegments: [Substring]
        if literal.contains("://") {
            guard let components = URLComponents(string: literal),
                  let scheme = components.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  components.host?.isEmpty == false,
                  components.user == nil,
                  components.password == nil,
                  components.query == nil,
                  components.fragment == nil,
                  !components.percentEncodedPath.hasSuffix("/") else {
                return false
            }
            pathSegments = components.percentEncodedPath.split(
                separator: "/",
                omittingEmptySubsequences: true
            )
            guard pathSegments.count >= 2,
                  !pathSegments.contains("_history") else {
                return false
            }
        } else {
            pathSegments = literal.split(separator: "/", omittingEmptySubsequences: false)
            guard pathSegments.count == 2 else {
                return false
            }
        }

        guard pathSegments[pathSegments.count - 2] == Substring(expectedResourceType) else {
            return false
        }
        return (try? GroveFHIRRepositoryID(String(pathSegments[pathSegments.count - 1]))) != nil
    }
}
