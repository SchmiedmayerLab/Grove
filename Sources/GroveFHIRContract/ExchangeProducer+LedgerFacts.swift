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


/// One `facts/<digest>` entry: the bytes stored, their digest, and the facts decoded back from them.
///
/// The digest is the SHA-256, base64url without padding, of the entry's bytes, so equal facts share one
/// entry across producer instances; a reservation names its digest, so an encoding that differs on another
/// platform only misses a deduplication. A producer prepares its facts once, when it is built.
struct PreparedFacts: Sendable {
    private struct Payload: Codable {
        enum CodingKeys: String, CodingKey {
            case version = "v"
            case application
            case host
            case studies
        }

        let version: Int
        let application: ApplicationPayload
        let host: HostPayload
        let studies: [StudyPayload]
    }

    private struct ApplicationPayload: Codable {
        let name: String
        let bundleIdentifier: String
        let version: String
        let build: String?
    }

    private struct HostPayload: Codable {
        let operatingSystemVersion: String
        let name: String?
        let manufacturer: String?
        let modelNumber: String?
    }

    private struct IdentifierPayload: Codable {
        let system: String
        let value: String
    }

    private struct StudyPayload: Codable {
        let study: IdentifierPayload
        /// The canonical as written, `<url>` or `<url>|<version>`; graphs read only its URL.
        let protocolURL: String?
        let protocolVersion: String
        let enrollment: IdentifierPayload
    }

    let bytes: Data
    let digest: String
    /// The facts as every graph sees them: decoded from ``bytes``, never the caller's values.
    let facts: ExchangeEventFacts

    /// Encodes `facts` and decodes them back the way a redelivery decodes the stored entry; `nil` when they do
    /// not survive that round trip, so no event could freeze them.
    init?(_ facts: ExchangeEventFacts) {
        let payload = Payload(
            version: LedgerEntryCoding.version,
            application: ApplicationPayload(
                name: facts.application.name,
                bundleIdentifier: facts.application.bundleIdentifier,
                version: facts.application.version,
                build: facts.application.build
            ),
            host: HostPayload(
                operatingSystemVersion: facts.host.operatingSystemVersion,
                name: facts.host.name,
                manufacturer: facts.host.manufacturer,
                modelNumber: facts.host.modelNumber
            ),
            studies: facts.studies.map { enrollment in
                StudyPayload(
                    study: IdentifierPayload(system: enrollment.study.system.rawValue, value: enrollment.study.value),
                    protocolURL: enrollment.protocolURL.value.map { canonical in
                        canonical.version.map { "\(canonical.url.absoluteString)|\($0)" } ?? canonical.url.absoluteString
                    },
                    protocolVersion: enrollment.protocolVersion,
                    enrollment: IdentifierPayload(system: enrollment.enrollment.system.rawValue, value: enrollment.enrollment.value)
                )
            }
        )
        guard let bytes = try? LedgerEntryCoding.encode(payload) else {
            return nil
        }
        let digest = Data(SHA256.hash(data: bytes)).base64URLEncodedStringWithoutPadding
        guard let decoded = try? Self.decode(bytes, key: LedgerKey.facts(digest)) else {
            return nil
        }
        self.bytes = bytes
        self.digest = digest
        self.facts = decoded
    }

    /// Rebuilds stored facts through the validating initializers; any fault makes the entry corrupt.
    static func decode(_ value: Data, key: String) throws -> ExchangeEventFacts {
        let payload = try LedgerEntryCoding.decode(Payload.self, from: value, key: key)
        guard let facts = facts(from: payload) else {
            throw ExchangeProducer.LedgerError.corruptEntry(key: key)
        }
        return facts
    }

    /// The facts a payload states, or `nil` when any validating initializer refuses a value.
    private static func facts(from payload: Payload) -> ExchangeEventFacts? {
        guard let application = try? ApplicationDevice(
            name: payload.application.name,
            bundleIdentifier: payload.application.bundleIdentifier,
            version: payload.application.version,
            build: payload.application.build
        ), let host = try? HostDevice(
            operatingSystemVersion: payload.host.operatingSystemVersion,
            name: payload.host.name,
            manufacturer: payload.host.manufacturer,
            modelNumber: payload.host.modelNumber
        ) else {
            return nil
        }
        var studies: [StudyEnrollment] = []
        for study in payload.studies {
            guard let studyIdentifier = identifier(study.study),
                  let enrollmentIdentifier = identifier(study.enrollment),
                  let canonical = protocolURL(study.protocolURL),
                  let rebuilt = try? StudyEnrollment(
                      study: studyIdentifier,
                      protocolURL: canonical,
                      protocolVersion: study.protocolVersion,
                      enrollment: enrollmentIdentifier
                  ) else {
                return nil
            }
            studies.append(rebuilt)
        }
        return ExchangeEventFacts(application: application, host: host, studies: studies)
    }

    private static func identifier(_ payload: IdentifierPayload) -> BusinessIdentifier? {
        try? BusinessIdentifier(system: IdentifierSystem(payload.system), value: payload.value)
    }

    /// The canonical as written; an absent one is an empty primitive, text that is no canonical is `nil`.
    private static func protocolURL(_ text: String?) -> FHIRPrimitive<Canonical>? {
        guard let text else {
            return FHIRPrimitive<Canonical>()
        }
        return text.asFHIRCanonicalPrimitive()
    }
}
