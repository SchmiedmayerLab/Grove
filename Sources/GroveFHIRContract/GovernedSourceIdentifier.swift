//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
public import ModelsR4


/// Governs an additional source-store identifier carried beside mandatory opaque Grove keys.
public enum GovernedSourceIdentifierDisclosurePolicy: Hashable, Sendable {
    /// Emit no clear source-store identifier.
    case omit
    /// Emit the exact source value under the caller-owned, store-scoped absolute system.
    case authorized(system: IdentifierSystem, type: GovernedSourceIdentifierType? = nil)

    /// The disclosed identifier for one exact native record value, or nil when the deployment
    /// omits clear source identifiers.
    public func identifier(for value: String) -> Identifier? {
        guard case let .authorized(system, type) = self else {
            return nil
        }
        return Identifier(
            system: FHIRPrimitive(FHIRURI(stringLiteral: system.rawValue)),
            type: type.map { type in
                CodeableConcept(coding: [
                    Coding(
                        code: type.code.asFHIRStringPrimitive(),
                        display: type.display?.asFHIRStringPrimitive(),
                        system: FHIRPrimitive(FHIRURI(stringLiteral: type.system.rawValue))
                    )
                ])
            },
            value: value.asFHIRStringPrimitive()
        )
    }
}


/// Optional non-Grove coding that explains an intentionally disclosed source-store identifier.
///
/// `Identifier.system` is normally sufficient. When a deployment adds `Identifier.type`, the
/// coding must be a valid R4 `code` and must not relabel the clear source value as one of Grove's
/// opaque graph identities.
public struct GovernedSourceIdentifierType: Hashable, Sendable {
    public enum ConfigurationError: Error, Equatable, Sendable {
        case emptyCode
        case invalidCodeLexicalForm
        case blankDisplay
        case groveGraphRoleSystem
    }

    public let system: IdentifierSystem
    public let code: String
    public let display: String?

    public init(
        system: IdentifierSystem,
        code: String,
        display: String? = nil
    ) throws(ConfigurationError) {
        guard !code.isEmpty else {
            throw .emptyCode
        }
        guard Self.isFHIRCode(code) else {
            throw .invalidCodeLexicalForm
        }
        if let display,
           display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw .blankDisplay
        }
        guard system.rawValue != Canonicals.identifierRoleCodeSystem.value?.url.absoluteString else {
            throw .groveGraphRoleSystem
        }
        self.system = system
        self.code = code
        self.display = display
    }

    /// R4 `code`: nonempty tokens separated by exactly one ASCII space, with no control scalar.
    private static func isFHIRCode(_ value: String) -> Bool {
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.contains("  ") else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            scalar == " " || (!CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !CharacterSet.controlCharacters.contains(scalar))
        }
    }
}
