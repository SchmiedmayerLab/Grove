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


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter {
    /// The output revisions a context fingerprint states.
    struct OutputRevisions: Hashable, Sendable {
        /// The revisions this build emits.
        static let current = OutputRevisions(assembler: ExchangeGraphAssembler.outputRevision, healthKit: HealthKitAssembly.outputRevision)

        let assembler: UInt
        let healthKit: UInt
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
                ["unit", device.stableUnitToken]
                    + Self.optionalParts(device.name) + Self.optionalParts(device.manufacturer) + Self.optionalParts(device.modelNumber)
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
extension HealthKitFHIRExporter.Record {
    /// The part of companion data the assembly cannot serialize: it throws the same, so the record is refused and no
    /// graph ever carries the part.
    private static let unserializable = "unserializable"

    /// The symptom count, then their lowercase UUIDs, sorted.
    private static func symptomParts(_ symptoms: [HKCategorySample]) -> [String] {
        ["symptoms", String(symptoms.count)] + symptoms.map { $0.uuid.uuidString.lowercased() }.sorted()
    }

    /// The SHA-256, base64url without padding, of `serialized`, or ``unserializable`` when it throws.
    private static func digest(_ serialized: () throws -> Data) -> String {
        guard let bytes = try? serialized() else {
            return unserializable
        }
        return Data(SHA256.hash(data: bytes)).base64URLEncodedStringWithoutPadding
    }

    /// The record content its event key does not version but its graph serializes: an ECG's symptom set (its
    /// Observation references their outputs) and voltages, a heartbeat series' beats and a route's locations. Each
    /// kind enters as a tag and the digest of exactly what the assembly serializes from it under `content`, the plan
    /// of the record's type. An ECG's voltages are read from its `evidence`, validated when the record was planned;
    /// without it they do not validate, and the record is refused.
    func companionParts(content: HealthKitContentPlan, evidence: HealthKitECGContent.Evidence?) -> [String] {
        switch self {
        case .sample:
            return []
        case .electrocardiogram(_, _, let symptoms):
            let voltages = evidence.map { evidence in Self.digest { try evidence.waveform.serialized() } } ?? Self.unserializable
            return Self.symptomParts(symptoms) + ["voltages", voltages]
        case let .heartbeatSeries(series, beats):
            return ["beats", Self.digest { try content.recordingDocument().beatIntervals(seriesStart: series.startDate, heartbeats: beats) }]
        case let .workoutRoute(_, locations):
            return ["locations", Self.digest { try content.recordingDocument().locationTrack(locations) }]
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitECGContent.Waveform {
    /// What the ECG Observation's SampledData and effective period state from the voltages, length-framed: the
    /// first and last offsets, the period and the data.
    func serialized() throws -> Data {
        try LengthFramedUTF8.encode([firstOffset.description, lastOffset.description, period.description, data])
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.WriterPolicy: ExchangeContextFingerprinted {
    /// The tag, then for an application set its count, which fixes how many parts follow, and its members in UTF-8
    /// byte order, so sets of the same strings, byte for byte, fingerprint equally whatever their insertion order.
    /// `Set` equality is canonical equivalence, so two sets that spell a member in different Unicode normalization
    /// forms compare equal yet fingerprint apart: a new sequence, never a reused one. A closure enters by its
    /// presence here; what it answers for each record enters that record's parts (`ResolvedPolicies`).
    package var fingerprintParts: [String] {
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
    package var fingerprintParts: [String] {
        switch self {
        case .application: ["application"]
        case .omit: ["omit"]
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.RecordingDevicePolicy: ExchangeContextFingerprinted {
    package var fingerprintParts: [String] {
        switch self {
        case .localIdentifier: ["localIdentifier"]
        case .omit: ["omit"]
        case .custom: ["custom"]
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.RolePolicy: ExchangeContextFingerprinted {
    package var fingerprintParts: [String] {
        switch self {
        case .assembler:
            ["assembler"]
        case .gatewayForOwnWrites:
            ["gatewayForOwnWrites"]
        case .gateway:
            ["gateway"]
        case .gatewayApplication(let application):
            ["gatewayApplication", application.name, application.bundleIdentifier, application.version] + Self.optionalParts(application.build)
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.Disclosure: ExchangeContextFingerprinted {
    package var fingerprintParts: [String] {
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
    package var fingerprintParts: [String] {
        switch self {
        case .none: ["none"]
        case .healthKitUUID: ["healthKitUUID"]
        }
    }
}

#endif
