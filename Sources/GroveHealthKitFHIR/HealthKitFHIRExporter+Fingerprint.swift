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
    /// followed by the record's own parts: what the writer and recording-device policies answered for its
    /// sample (`ResolvedPolicies`) and its companion data (`Input.companionParts`). A stored reservation is
    /// reused only under an equal fingerprint, so a Grove update that changes output, any option change, a
    /// policy closure that answers otherwise, other companion data, or another participant over the same
    /// ledger never reuses an event identifier for other bytes.
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


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter {
    /// What the writer and recording-device policies answer for one sample, resolved once per input that names it,
    /// before its event is reserved: the event's fingerprint covers these answers and its graph states them, so a
    /// ``WriterPolicy/classify(_:)`` closure or a custom ``RecordingDevicePolicy`` resolver that answers otherwise
    /// for a reserved record takes a new sequence instead of restating the reserved event.
    struct ResolvedPolicies: ExchangeContextFingerprinted {
        let writer: HealthKitWriter
        /// `nil` when the sample names no `HKDevice` or the policy declines it.
        let recordingDevice: RecordingDevice?

        /// The writer tag, then the recording device's: `none`, or `unit` and every value of the device the graph
        /// states, its token (which keys the Device's identities) and its optional name, manufacturer and model.
        var fingerprintParts: [String] {
            let device = recordingDevice.map { device in
                ["unit", device.stableUnitToken] + optionalParts(device.name) + optionalParts(device.manufacturer) + optionalParts(device.modelNumber)
            }
            return ["writer"] + writer.fingerprintParts + ["recordingDevice"] + (device ?? ["none"])
        }

        init(_ sample: HKSample, options: Options) {
            self.writer = options.writer.classification(of: sample.sourceRevision.source)
            self.recordingDevice = sample.device.flatMap(options.recordingDevice.recordingDevice(for:))
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.Input {
    /// The record content its event key does not version but its graph serializes: an ECG's symptom set (its
    /// Observation references their outputs) and voltages, a heartbeat series' beats and a route's locations. Each
    /// kind enters as a tag and the digest of exactly what the assembly serializes from it.
    var companionParts: [String] {
        switch self {
        case .record(.sample):
            return []
        case let .electrocardiogramEvidence(_, evidence, symptoms):
            return Self.symptomParts(symptoms) + ["voltages", Self.digest { try evidence.waveform.serialized() }]
        case let .record(.electrocardiogram(ecg, voltages, symptoms)):
            // A planned input still carries raw voltages only when they do not validate, and the record is refused.
            let record = HealthKitECGRecord(electrocardiogram: ecg, voltageMeasurements: voltages)
            return Self.symptomParts(symptoms) + ["voltages", Self.digest { try HealthKitECGEvidence(record).waveform.serialized() }]
        case let .record(.heartbeatSeries(series, beats)):
            return ["beats", Self.digest { try HealthKitConverter.beatIntervalPayload(seriesStart: series.startDate, heartbeats: beats) }]
        case let .record(.workoutRoute(_, locations)):
            return ["locations", Self.digest { try HealthKitConverter.locationTrackPayload(locations) }]
        }
    }

    /// The symptom count, then their lowercase UUIDs, sorted.
    private static func symptomParts(_ symptoms: [HKCategorySample]) -> [String] {
        ["symptoms", String(symptoms.count)] + symptoms.map { $0.uuid.uuidString.lowercased() }.sorted()
    }

    /// The SHA-256, base64url without padding, of `serialized`, or `unserializable` when it throws: the assembly
    /// throws the same, so the record is refused and no graph ever carries the part.
    private static func digest(_ serialized: () throws -> Data) -> String {
        guard let bytes = try? serialized() else {
            return "unserializable"
        }
        return Data(SHA256.hash(data: bytes)).base64URLEncodedStringWithoutPadding
    }
}


extension HealthKitECGValidatedWaveform {
    /// What the ECG Observation's SampledData and effective period state from the voltages, length-framed: the
    /// first and last offsets, the period and the data.
    func serialized() throws -> Data {
        try LengthFramedUTF8.encode([firstOffsetSeconds.description, lastOffsetSeconds.description, periodMilliseconds.description, data])
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
    /// byte order, so sets of the same strings, byte for byte, fingerprint equally whatever their insertion order.
    /// `Set` equality is canonical equivalence, so two sets that spell a member in different Unicode normalization
    /// forms compare equal yet fingerprint apart: a new sequence, never a reused one. A closure enters by its
    /// presence here; what it answers for each record enters that record's parts (`ResolvedPolicies`).
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


extension HealthKitWriter: ExchangeContextFingerprinted {
    var fingerprintParts: [String] {
        switch self {
        case .application: ["application"]
        case .omit: ["omit"]
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
