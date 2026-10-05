//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import ModelsR4


/// A configuration value as a context fingerprint states it: a tag naming the case, then its values.
///
/// Each conformance derives its parts by an exhaustive `switch` without a `default`, so a new case or
/// associated value cannot enter an exporter without entering the fingerprint. A case's tag fixes how many
/// parts follow it, so the length-framed sequence stays unambiguous.
package protocol ExchangeContextFingerprinted {
    var fingerprintParts: [String] { get }
}


/// Everything that shapes one exporter's graphs but is not frozen with an event: the output revisions, the
/// identity scope, the subject, the repository scope and every setting of the exporter.
///
/// A request's fingerprint is the SHA-256, base64url without padding, of the length-framed call parts
/// followed by the record's own parts, such as what a policy answered for the record and record content its
/// event key does not version. A stored reservation is reused only under an equal fingerprint, so a Grove update
/// that changes output, any setting change, other record parts, or another participant over the same ledger
/// never reuses an event identifier for other bytes.
package struct ExchangeRequestContext: Sendable {
    /// The length-framed parts every request of the exporter starts with, in order.
    private let framedCallParts: Data

    /// The context of one exporter.
    ///
    /// The call parts are, in order: `label`, `outputRevisions` and each revision, `identityScope` and the scope's
    /// ledger fingerprint, `subject` and the subject's parts, `repositoryScope` with its system and value, then
    /// each setting's property name followed by its parts.
    ///
    /// - Parameters:
    ///   - label: The adapter's versioned context label, such as `grove-healthkit-context-v0`; it fixes how many
    ///     revisions follow.
    ///   - outputRevisions: The revision of every builder the exporter's graphs pass through, the shared
    ///     assembler's first.
    ///   - producer: The producer whose identity scope and subject every graph states.
    ///   - repositoryScope: The business identifier naming the exporter's source store.
    ///   - settings: Every stored setting of the exporter, by property name, in declaration order.
    package init(
        label: String,
        outputRevisions: [UInt],
        producer: ExchangeProducer,
        repositoryScope: BusinessIdentifier,
        settings: [(property: String, parts: [String])]
    ) {
        var parts = [label, "outputRevisions"] + outputRevisions.map { String($0) }
        parts += ["identityScope", producer.identityScope.ledgerFingerprint, "subject"]
        parts += producer.subject.fingerprintParts
        parts += ["repositoryScope", repositoryScope.system.rawValue, repositoryScope.value]
        for setting in settings {
            parts += [setting.property] + setting.parts
        }
        self.framedCallParts = Self.framed(parts)
    }

    private static func framed(_ parts: [String]) -> Data {
        do {
            return try Data(lengthFramedUTF8: parts)
        } catch {
            preconditionFailure("A context fingerprint part exceeds the framing limit: \(error)")
        }
    }

    /// The request of one event key with the record parts the key does not version.
    package func request(for key: ExchangeEventKey, recordParts: [String] = []) -> ExchangeEventRequest {
        let digest = SHA256.hash(data: framedCallParts + Self.framed(recordParts))
        return ExchangeEventRequest(key: key, fingerprint: Data(digest).base64URLEncodedStringWithoutPadding)
    }
}


extension ExchangeContextFingerprinted {
    /// An optional value's parts: a presence tag, then the value.
    package static func optionalParts(_ value: String?) -> [String] {
        value.map { ["some", $0] } ?? ["none"]
    }
}


extension Subject: ExchangeContextFingerprinted {
    package var fingerprintParts: [String] {
        switch self {
        case .logical(let identifier):
            return ["logical", identifier.system.rawValue, identifier.value]
        case let .bundled(identifier, patient):
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            // A Patient that cannot be encoded cannot be emitted either, so its events never carry a graph; no JSON
            // text equals the constant, so it never matches an encodable Patient's fingerprint.
            let patientJSON = (try? encoder.encode(patient)).map { String(decoding: $0, as: UTF8.self) } ?? "unencodable"
            return ["bundled", identifier.system.rawValue, identifier.value, patientJSON]
        }
    }
}


extension GovernedSourceIdentifierDisclosurePolicy: ExchangeContextFingerprinted {
    package var fingerprintParts: [String] {
        switch self {
        case .omit:
            return ["omit"]
        case let .authorized(system, type):
            // The type changes `Identifier.type` on every disclosed identifier.
            let typeParts = type.map { ["typed", $0.system.rawValue, $0.code] + Self.optionalParts($0.display) } ?? ["untyped"]
            return ["authorized", system.rawValue] + typeParts
        }
    }
}
