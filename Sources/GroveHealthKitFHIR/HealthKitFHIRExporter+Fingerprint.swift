//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import CryptoKit
import Foundation
import GroveFHIRContract
import HealthKit
import ModelsR4


/// A configuration value as the context fingerprint states it: a tag naming the case, then its values.
///
/// Each conformance derives its parts by an exhaustive `switch` without a `default`, so a new case or
/// associated value cannot enter the exporter without entering the fingerprint. A case's tag fixes how many
/// parts follow it, so the length-framed sequence stays unambiguous.
protocol ExchangeContextFingerprinted {
    var fingerprintParts: [String] { get }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter {
    /// The output revisions a context fingerprint states.
    struct OutputRevisions: Hashable, Sendable {
        /// The revisions this build emits.
        static let current = OutputRevisions(assembler: ExchangeGraphAssembler.outputRevision, healthKit: HealthKitAssembly.outputRevision)

        let assembler: UInt
        let healthKit: UInt
    }

    /// Everything that shapes this exporter's graphs but is not frozen with an event: the output revisions,
    /// the identity scope, the subject, the repository scope and every option.
    ///
    /// A request's fingerprint is the SHA-256, base64url without padding, of the length-framed call parts
    /// followed by the record's own parts. A stored reservation is reused only under an equal fingerprint, so
    /// a Grove update that changes output, any option change, or another participant over the same ledger
    /// never reuses an event identifier for other bytes. A ``WriterPolicy/classify(_:)`` closure and a custom
    /// ``RecordingDevicePolicy`` resolver enter by their presence only; their behaviour is not fingerprinted.
    struct ExportContext: Sendable {
        /// The length-framed parts every request of this exporter starts with, in order.
        private let framedCallParts: Data

        init(producer: ExchangeProducer, repositoryScope: BusinessIdentifier, options: Options, revisions: OutputRevisions) {
            var parts = [
                "grove-healthkit-context-v0",
                "outputRevisions", String(revisions.assembler), String(revisions.healthKit),
                "identityScope", producer.identityScope.ledgerFingerprint,
                "subject"
            ]
            parts += producer.subject.fingerprintParts
            parts += ["repositoryScope", repositoryScope.system.rawValue, repositoryScope.value]
            for option in options.fingerprintParts {
                parts += [option.property] + option.parts
            }
            self.framedCallParts = Self.framed(parts)
        }

        private static func framed(_ parts: [String]) -> Data {
            do {
                return try LengthFramedUTF8.encode(parts)
            } catch {
                preconditionFailure("A context fingerprint part exceeds the framing limit: \(error)")
            }
        }

        /// The request of one event key with the record parts the key does not version.
        func request(for key: ExchangeEventKey, recordParts: [String] = []) -> ExchangeEventRequest {
            let digest = SHA256.hash(data: framedCallParts + Self.framed(recordParts))
            return ExchangeEventRequest(key: key, fingerprint: Data(digest).base64URLEncodedStringWithoutPadding)
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.Options {
    /// Every stored option and its fingerprint parts, in declaration order. The completeness test compares
    /// the property names with the stored properties ``HealthKitFHIRExporter/Options`` declares.
    var fingerprintParts: [(property: String, parts: [String])] {
        let options: [(String, any ExchangeContextFingerprinted)] = [
            ("writer", writer),
            ("recordingDevice", recordingDevice),
            ("role", role),
            ("nativeIdentifier", nativeIdentifier),
            ("udi", udi),
            ("route", route),
            ("legacyBundleID", legacyBundleID)
        ]
        return options.map { (property: $0.0, parts: $0.1.fingerprintParts) }
    }
}


/// An optional value's parts: a presence tag, then the value.
private func optionalParts(_ value: String?) -> [String] {
    value.map { ["some", $0] } ?? ["none"]
}


extension Subject: ExchangeContextFingerprinted {
    var fingerprintParts: [String] {
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


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.WriterPolicy: ExchangeContextFingerprinted {
    /// The tag, then for an application set its count, which fixes how many parts follow, and its members in UTF-8
    /// byte order, so equal sets fingerprint equally whatever their insertion order or the platform's collation. A
    /// closure enters by its presence only; how it classifies is the caller's to keep stable.
    var fingerprintParts: [String] {
        switch self {
        case .omit:
            return ["omit"]
        case .applications(let bundleIdentifiers):
            let sorted = bundleIdentifiers.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            return ["applications", String(sorted.count)] + sorted
        case .classify:
            return ["classify"]
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.RecordingDevicePolicy: ExchangeContextFingerprinted {
    var fingerprintParts: [String] {
        switch self {
        case .localIdentifier: ["localIdentifier"]
        case .omit: ["omit"]
        case .custom: ["custom"]
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.RolePolicy: ExchangeContextFingerprinted {
    var fingerprintParts: [String] {
        switch self {
        case .assembler:
            ["assembler"]
        case .gatewayForOwnWrites:
            ["gatewayForOwnWrites"]
        case .gateway:
            ["gateway"]
        case .gatewayApplication(let application):
            ["gatewayApplication", application.name, application.bundleIdentifier, application.version] + optionalParts(application.build)
        }
    }
}


extension GovernedSourceIdentifierDisclosurePolicy: ExchangeContextFingerprinted {
    var fingerprintParts: [String] {
        switch self {
        case .omit:
            return ["omit"]
        case let .authorized(system, type):
            // The type changes `Identifier.type` on every disclosed identifier.
            let typeParts = type.map { ["typed", $0.system.rawValue, $0.code] + optionalParts($0.display) } ?? ["untyped"]
            return ["authorized", system.rawValue] + typeParts
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.Disclosure: ExchangeContextFingerprinted {
    var fingerprintParts: [String] {
        switch self {
        case .omit: ["omit"]
        case .authorized: ["authorized"]
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.LegacyBundleID: ExchangeContextFingerprinted {
    /// Deprecated only because it names the deprecated case; the fingerprint reads it through the protocol.
    @available(*, deprecated, message: "Names the transitional legacy case; read it through ExchangeContextFingerprinted.")
    var fingerprintParts: [String] {
        switch self {
        case .none: ["none"]
        case .healthKitUUID: ["healthKitUUID"]
        }
    }
}

#endif
