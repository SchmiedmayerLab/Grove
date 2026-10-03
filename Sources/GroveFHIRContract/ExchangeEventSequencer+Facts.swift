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
/// platform only misses a deduplication.
struct PreparedFacts {
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

    init(_ facts: ExchangeEventFacts) throws {
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
        let bytes = try LedgerEntryCoding.encode(payload)
        let digest = Data(SHA256.hash(data: bytes)).base64URLEncodedStringWithoutPadding
        self.bytes = bytes
        self.digest = digest
        self.facts = try Self.decode(bytes, key: LedgerKey.facts(digest))
    }

    /// Rebuilds stored facts through the validating initializers; any fault makes the entry corrupt.
    static func decode(_ value: Data, key: String) throws -> ExchangeEventFacts {
        let payload = try LedgerEntryCoding.decode(Payload.self, from: value, key: key)
        do {
            let application = try ApplicationDevice(
                name: payload.application.name,
                bundleIdentifier: payload.application.bundleIdentifier,
                version: payload.application.version,
                build: payload.application.build
            )
            let host = try HostDevice(
                operatingSystemVersion: payload.host.operatingSystemVersion,
                name: payload.host.name,
                manufacturer: payload.host.manufacturer,
                modelNumber: payload.host.modelNumber
            )
            let studies = try payload.studies.map { study in
                try StudyEnrollment(
                    study: try identifier(study.study),
                    protocolURL: try protocolURL(study.protocolURL),
                    protocolVersion: study.protocolVersion,
                    enrollment: try identifier(study.enrollment)
                )
            }
            return ExchangeEventFacts(application: application, host: host, studies: studies)
        } catch {
            throw ExchangeEventSequencer.LedgerError.corruptEntry(key: key)
        }
    }

    private static func identifier(_ payload: IdentifierPayload) throws -> BusinessIdentifier {
        try BusinessIdentifier(system: IdentifierSystem(payload.system), value: payload.value)
    }

    private static func protocolURL(_ text: String?) throws -> FHIRPrimitive<Canonical> {
        guard let text else {
            return FHIRPrimitive<Canonical>()
        }
        guard let canonical = text.asFHIRCanonicalPrimitive() else {
            throw ExchangeEventSequencer.LedgerError.corruptEntry(key: text)
        }
        return canonical
    }
}
