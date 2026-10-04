//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
@testable import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


/// What one case pins: the graph the API emitted, what it reported losing, in order, and what it reported about
/// the graph's record and identities.
struct GoldenOutput: Sendable {
    let graph: ExchangeGraph
    /// Each warning as the outline spells it: the registry code, then the field, device name or keys it names.
    let renderedWarnings: [String]
    /// The record the conversion names; `nil` for a retraction, which names its record through its targets.
    let source: HealthKitSourceRecord?
    /// The identities the conversion reported; `nil` where the API reports none.
    let identifiers: ExchangeGraphIdentifiers?

    init(graph: ExchangeGraph, renderedWarnings: [String], source: HealthKitSourceRecord?, identifiers: ExchangeGraphIdentifiers?) {
        self.graph = graph
        self.renderedWarnings = renderedWarnings
        self.source = source
        self.identifiers = identifiers
    }

    init(_ conversion: HealthKitConversion) {
        graph = conversion.graph
        renderedWarnings = conversion.warnings.map { warning in
            switch warning {
            case .recordingDeviceOmitted(let deviceName):
                "\(warning.diagnostic.code)(\(deviceName ?? ""))"
            case .sourceOffsetUnavailable(let field):
                "\(warning.diagnostic.code)@\(field)"
            case .unmodeledMetadataWithheld(let keys):
                "\(warning.diagnostic.code)(\(keys.joined(separator: ",")))"
            }
        }
        source = conversion.source
        identifiers = conversion.identifiers
    }

    init(_ retraction: RetractionEvent) {
        graph = retraction.graph
        renderedWarnings = []
        source = nil
        identifiers = nil
    }

    /// The primary graph of `set`, which must carry exactly `companions` companion graphs: a case that pins only
    /// the primary would otherwise let a spurious or a lost companion pass.
    init(primaryOf set: HealthKitConversionSet, companions: Int = 0) throws {
        guard set.companions.count == companions else {
            throw GoldenCaseError.unexpectedCompanions(set.companions.count)
        }
        self.init(set.primary)
    }
}


/// One pinned wire shape: a stable name, the event sequence its context states, and how the
/// converter's public API (or, for ECGs, the internal seam the existing tests use) produces it.
///
/// Sequences are append-only: a new case takes the next free number of its group so that adding a
/// case never re-mints the identities of an existing golden.
struct GoldenCase: Sendable, CustomTestStringConvertible {
    let name: String
    let sequence: UInt64
    private let produce: @Sendable (UInt64) throws -> GoldenOutput

    var testDescription: String { name }

    init(_ name: String, sequence: UInt64, produce: @escaping @Sendable (_ sequence: UInt64) throws -> GoldenOutput) {
        self.name = name
        self.sequence = sequence
        self.produce = produce
    }

    func output() throws -> GoldenOutput {
        try produce(sequence)
    }
}


/// The fixed inputs every golden case is built from. Nothing here reads the clock, the process
/// or the host, so two runs on two machines mint the same identities and the same bytes.
enum GoldenFixtures {
    /// What a case varies beyond its sample: every field defaults to the test context's fixed facts.
    struct Inputs: Sendable {
        /// The default inputs with the sample's source classified as an application, for the cases that pin how a
        /// writer travels; by default no writer is stated.
        static var applicationWriter: Inputs {
            var inputs = Inputs()
            inputs.options.writer = .application
            return inputs
        }

        var subject: Subject = .testPatient
        var converter: ApplicationDevice = .test
        var converterHost: HostDevice = .test
        var converterRole: ConverterRole = .assembler
        var studies: [StudyEnrollment] = []
        var repositoryIDs: [ExchangeGraphNode: RepositoryID] = [:]
        var options = HealthKitConversionOptions()
    }

    /// 2026-08-17T23:30:00Z, in whole seconds: the conversion instant of every case.
    static let conversionInstant = ExchangeEventContext.testInstant
    /// 2026-08-17T22:30:00Z (15:30 in Los Angeles): when every sample starts.
    static let sampleStart = Date(timeIntervalSince1970: 1_787_005_800)
    static let timeZone = "America/Los_Angeles"
    static let nativeIdentifierSystem: IdentifierSystem = "https://study.example.org/fhir/NamingSystem/healthkit-store"
    static let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

    /// A watch that names its physical unit and carries a UDI, so the recording Device and the UDI disclosure both apply.
    static let watch = HKDevice(
        name: "Apple Watch",
        manufacturer: "Apple Inc.",
        model: "Watch7,12",
        hardwareVersion: "Watch7,12",
        firmwareVersion: "1.0",
        softwareVersion: "26.2.1",
        localIdentifier: "6C4B1D1E-0000-4000-8000-000000000001",
        udiDeviceIdentifier: "(01)00844588003288"
    )

    /// The same watch as HealthKit reports it without a per-unit token: no recording Device, and the omission is reported.
    static let watchWithoutUnitToken = HKDevice(
        name: "Apple Watch",
        manufacturer: "Apple Inc.",
        model: "Watch7,12",
        hardwareVersion: "Watch7,12",
        firmwareVersion: "1.0",
        softwareVersion: "26.2.1",
        localIdentifier: nil,
        udiDeviceIdentifier: nil
    )

    /// A third-party application that wrote the sample on its own phone.
    static let foreignWriter = StoredSampleFixtures.Writer(
        name: "Example Writer",
        bundleIdentifier: "org.example.writer",
        version: "42",
        productType: "iPhone17,1"
    )

    static let timeZoneMetadata: [String: any Sendable] = [HKMetadataKeyTimeZone: timeZone]

    /// A per-case UUID that reads as one: `3A7E5C10-0000-4000-8000-0000000000NN`.
    static func uuid(_ ordinal: UInt8) -> UUID {
        UUID(uuid: (0x3A, 0x7E, 0x5C, 0x10, 0x00, 0x00, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, ordinal))
    }

    /// The context of one case: the test identity scope and key, the fixed producer instance, and `sequence`.
    static func context(sequence: UInt64, _ inputs: Inputs = Inputs()) throws -> HealthKitConversionContext {
        let base = ExchangeEventContext.test()
        let event = try ExchangeEventIdentifier(
            system: base.identityScope.systems.event,
            producerInstance: base.event.producerInstance,
            sequence: EventSequence(sequence)
        )
        return HealthKitConversionContext(
            event: ExchangeEventContext(
                subject: inputs.subject,
                event: event,
                identityScope: base.identityScope,
                repositoryScope: base.repositoryScope,
                application: inputs.converter,
                host: inputs.converterHost,
                conversionInstant: conversionInstant,
                converterRole: inputs.converterRole,
                studies: inputs.studies,
                repositoryIDs: inputs.repositoryIDs
            ),
            options: inputs.options
        )
    }

    /// The one graph of `sample` under the old public entry point, with what the conversion reported losing.
    static func convert(_ sample: HKSample, sequence: UInt64, _ inputs: Inputs = Inputs()) throws -> GoldenOutput {
        try GoldenOutput(primaryOf: HealthKitConverter().convert(sample, context: context(sequence: sequence, inputs)))
    }

    /// A 72 bpm heart rate; `end` stays the start instant unless a case states an interval.
    static func heartRate(
        uuid: UUID,
        device: HKDevice? = nil,
        metadata: [String: any Sendable]? = timeZoneMetadata, // swiftlint:disable:this discouraged_optional_collection
        writer: StoredSampleFixtures.Writer? = nil,
        end: Date? = nil
    ) throws -> HKQuantitySample {
        let sample = HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: beatsPerMinute, doubleValue: 72),
            start: sampleStart,
            end: end ?? sampleStart,
            device: device,
            metadata: metadata
        )
        return try StoredSampleFixtures.stored(sample, uuid: uuid, writer: writer)
    }

    /// A point-in-time quantity at the sample start, attributed to no writer.
    static func quantity(
        _ type: HKQuantityTypeIdentifier,
        _ quantity: HKQuantity,
        uuid: UUID,
        device: HKDevice? = nil,
        metadata: [String: any Sendable]? = timeZoneMetadata // swiftlint:disable:this discouraged_optional_collection
    ) throws -> HKQuantitySample {
        let sample = HKQuantitySample(
            type: HKQuantityType(type),
            quantity: quantity,
            start: sampleStart,
            end: sampleStart,
            device: device,
            metadata: metadata
        )
        return try StoredSampleFixtures.stored(sample, uuid: uuid)
    }

    static func category(
        _ type: HKCategoryTypeIdentifier,
        value: Int,
        uuid: UUID,
        duration: TimeInterval,
        device: HKDevice? = watch
    ) throws -> HKCategorySample {
        let sample = HKCategorySample(
            type: HKCategoryType(type),
            value: value,
            start: sampleStart,
            end: sampleStart.addingTimeInterval(duration),
            device: device,
            metadata: timeZoneMetadata
        )
        return try StoredSampleFixtures.stored(sample, uuid: uuid)
    }

    /// The converter the sample's own writer belongs to: the same bundle identifier, with the version and build given.
    static func selfConverter(version: String, build: String?) -> ApplicationDevice {
        ApplicationDevice.test(name: "Grove Test", bundleIdentifier: ApplicationDevice.test.bundleIdentifier, version: version, build: build)
    }

    /// A one-hour run in Berlin with 640 kcal and 10 km; with events, a pause, a resume, eight laps and two
    /// segments, which the converter withholds. `device` is the recorder; `userEntered` marks it entered by hand.
    static func workout(withEvents: Bool, device: HKDevice? = nil, userEntered: Bool = false) -> HKWorkout {
        let begin = Date(timeIntervalSince1970: 1_786_000_000)
        var events: [HKWorkoutEvent] = []
        if withEvents {
            events = [
                HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: begin.addingTimeInterval(600), duration: 0), metadata: nil),
                HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: begin.addingTimeInterval(660), duration: 0), metadata: nil)
            ]
            events += (0..<8).map { lap in
                HKWorkoutEvent(type: .lap, dateInterval: DateInterval(start: begin.addingTimeInterval(Double(lap) * 400), duration: 400), metadata: nil)
            }
            events += (0..<2).map { segment in
                HKWorkoutEvent(
                    type: .segment,
                    dateInterval: DateInterval(start: begin.addingTimeInterval(Double(segment) * 1_800), duration: 1_800),
                    metadata: nil
                )
            }
        }
        return HKWorkout(
            activityType: .running,
            start: begin,
            end: begin.addingTimeInterval(3_600),
            workoutEvents: events.isEmpty ? nil : events,
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 640),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 10_000),
            device: device,
            metadata: userEntered ? [HKMetadataKeyTimeZone: "Europe/Berlin", HKMetadataKeyWasUserEntered: true] : [HKMetadataKeyTimeZone: "Europe/Berlin"]
        )
    }

    /// The sample's writer when the converter wrote it: the converter's bundle identifier, stating `revisionVersion`.
    static func selfWriter(revisionVersion: String?) -> StoredSampleFixtures.Writer {
        StoredSampleFixtures.Writer(
            name: "Grove Test",
            bundleIdentifier: ApplicationDevice.test.bundleIdentifier,
            version: revisionVersion,
            productType: "iPhone17,1"
        )
    }
}


extension GoldenOutput {
    /// Where what the conversion reported disagrees with the graph it reported it for, read from the graph's own
    /// tokens: each reported output and Device is the entry its fullUrl names and carries that identity, the
    /// Provenance is the one entry at its entry-node fullUrl, the source record and artifact identities are on the
    /// primary output, every output and Device entry is reported (a distinct gateway application aside, which no
    /// identity names), and the source is the record the graph's source identity is minted from. Empty for a
    /// retraction, which reports neither.
    func reportMismatches(identityScope: OpaqueIdentityScope, repositoryScope: BusinessIdentifier) throws -> [String] {
        guard let identifiers, let source else {
            return []
        }
        let entries: [LosslessJSONValue] = try LosslessJSONValue(parsing: graph.json)["entry"]?.elements ?? []
        var byURL: [String: LosslessJSONValue] = [:]
        for entry in entries {
            byURL[entry["fullUrl"]?.text ?? ""] = entry
        }
        func carries(_ url: String, _ identity: RoledIdentifier?) -> Bool {
            guard let identity else {
                return true
            }
            let stated: [LosslessJSONValue] = byURL[url]?["resource"]?["identifier"]?.elements ?? []
            return stated.contains { $0["system"]?.text == identity.identifier.system.rawValue && $0["value"]?.text == identity.identifier.value }
        }
        func urls(ofTypes types: Set<String>) -> Set<String> {
            Set(entries.filter { types.contains($0["resource"]?["resourceType"]?.text ?? "") }.compactMap { $0["fullUrl"]?.text })
        }
        let optionalDevices: [RoledIdentifier] = [
            identifiers.recordingDeviceSnapshot, identifiers.writerSnapshot, identifiers.writerHostSnapshot
        ].compactMap(\.self)
        let devices: [RoledIdentifier] = [identifiers.applicationSnapshot, identifiers.hostSnapshot] + optionalDevices
        let outputs: [RoledIdentifier] = [identifiers.primaryOutput] + identifiers.childOutputs
        var mismatches: [String] = []
        for node in outputs + devices where !carries(try node.fullURLString, node) {
            mismatches.append("node \(node.identifier.value)")
        }
        // A Provenance carries no identifier; its entry-node key is its fullUrl.
        if urls(ofTypes: ["Provenance"]) != [try identifiers.provenance.fullURLString] {
            mismatches.append("provenance")
        }
        let primaryURL = try identifiers.primaryOutput.fullURLString
        if identifiers.event != graph.eventIdentifier.identifier {
            mismatches.append("event")
        }
        if !carries(primaryURL, identifiers.sourceRecord) || !carries(primaryURL, identifiers.sourceArtifact) {
            mismatches.append("source record or artifact identity")
        }
        if urls(ofTypes: ["Observation", "DocumentReference"]) != Set(try outputs.map { try $0.fullURLString }) {
            mismatches.append("outputs")
        }
        let deviceURLs = Set(try devices.map { try $0.fullURLString })
        let extensions: [LosslessJSONValue] = entries.flatMap { $0["resource"]?["extension"]?.elements ?? [] }
        let gatewayURLs = Set(extensions.filter { $0["url"]?.text == Canonicals.gatewayDevice.value?.url.absoluteString }
            .compactMap { $0["valueReference"]?["reference"]?.text })
        if urls(ofTypes: ["Device"]).subtracting(gatewayURLs.subtracting(deviceURLs)) != deviceURLs {
            mismatches.append("devices")
        }
        let minted = try identityScope.sourceRecord(
            adapterID: HealthKitConverter.adapterID,
            sourceType: source.type.rawValue,
            repositoryScope: repositoryScope,
            nativeRecordID: source.uuid.uuidString.lowercased()
        )
        if minted.identifier != identifiers.sourceRecord {
            mismatches.append("source")
        }
        return mismatches
    }
}

#endif
