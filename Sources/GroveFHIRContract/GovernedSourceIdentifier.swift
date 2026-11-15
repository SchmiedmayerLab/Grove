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
    ///
    /// For a HealthKit sample that carries a sync identifier, this also emits the exact sync identifier text under a
    /// system derived from this one, which names the writing application's bundle identifier.
    case authorized(system: IdentifierSystem, type: IdentifierType? = nil)

    /// The disclosed identifier for one exact native record value, or nil when the deployment
    /// omits clear source identifiers.
    public func identifier(for value: String) -> Identifier? {
        guard case let .authorized(system, type) = self else {
            return nil
        }
        return Identifier(
            system: system.uri,
            type: type.map { type in
                CodeableConcept(coding: [
                    Coding(
                        code: type.code.asFHIRStringPrimitive(),
                        display: type.display?.asFHIRStringPrimitive(),
                        system: type.system.uri
                    )
                ])
            },
            value: value.asFHIRStringPrimitive()
        )
    }

    /// The disclosed native record identifier a retraction target carries, or nil when the deployment
    /// omits clear source identifiers.
    package func nativeRecordIdentifier(for value: String) -> BusinessIdentifier? {
        guard case let .authorized(system, _) = self else {
            return nil
        }
        return try? BusinessIdentifier(system: system, value: value)
    }
}


extension GovernedSourceIdentifierDisclosurePolicy {
    /// Whether this policy discloses clear source identifiers.
    package var isAuthorized: Bool {
        if case .authorized = self { true } else { false }
    }

    /// What every readable sync identifier system under the store-scoped `system` starts with; the writing application's
    /// segment follows.
    package static func syncIdentifierSystemPrefix(in system: IdentifierSystem) -> String {
        "\(system.rawValue)/\(HealthKitContract.syncIdentifierSystemPathSegment)/"
    }

    /// Whether `bundleIdentifier` can be the final segment of a readable sync identifier's system: nonempty, and only
    /// ASCII letters, digits, hyphens and periods, the characters of an Apple bundle identifier.
    package static func isSyncIdentifierWriterSegment(_ bundleIdentifier: String) -> Bool {
        !bundleIdentifier.isEmpty && bundleIdentifier.utf8.allSatisfy { $0.isASCIIAlphaNumeric || $0 == 0x2D || $0 == 0x2E }
    }

    /// The readable HealthKit sync identifier of one writer record: the exact sync identifier text, typed
    /// `healthkit-sync-id`, under the authorized store-scoped system followed by the `healthkit-sync-identifier` path
    /// segment and the writing application's bundle identifier. Equal text from another writing application or another
    /// store has another system (HealthKit guide `mapping.md`, readable sync identifier).
    ///
    /// It is nil when the deployment omits clear source identifiers, and when the bundle identifier is no writer segment:
    /// it is never escaped, encoded or substituted.
    package func syncIdentifier(for record: ExchangeOutputDraft.WriterRecord) -> Identifier? {
        guard case let .authorized(system, _) = self, Self.isSyncIdentifierWriterSegment(record.writerApplication) else {
            return nil
        }
        return Identifier(
            system: FHIRPrimitive(FHIRURI(stringLiteral: Self.syncIdentifierSystemPrefix(in: system) + record.writerApplication)),
            type: CodeableConcept(coding: [
                Coding(
                    code: HealthKitContract.syncIdentifierTypeCode.asFHIRStringPrimitive(),
                    system: HealthKitContract.syncIdentifierTypeSystem
                )
            ]),
            value: record.syncIdentifier.asFHIRStringPrimitive()
        )
    }
}


extension GovernedSourceIdentifierDisclosurePolicy {
    /// Optional non-Grove coding that explains an intentionally disclosed source-store identifier.
    ///
    /// `Identifier.system` is normally sufficient. When a deployment adds `Identifier.type`, the
    /// coding must be a valid R4 `code` and must not relabel the clear source value as one of Grove's
    /// opaque graph identities.
    public struct IdentifierType: Hashable, Sendable {
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
}
