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


/// What one case pins: the graph the exporter delivered, what it reported losing, in order, and the record it reported
/// the graph for.
struct GoldenOutput: Sendable {
    let graph: ExchangeGraph
    /// Each warning as the outline spells it: the registry code, then the element it names.
    let renderedWarnings: [String]
    /// The record the exporter reported the graph for, which the golden test checks against the graph's source identity.
    let source: HealthKitFHIRExporter.Export.Source

    /// What one export delivered; an export without a graph throws.
    init(_ export: HealthKitFHIRExporter.Export) throws {
        guard let graph = export.graph else {
            throw GoldenCaseError.notExported(String(describing: export.outcome))
        }
        self.graph = graph
        renderedWarnings = export.warnings.map { "\($0.code)@\($0.location)" }
        source = export.source
    }

    /// What one retraction delivered, which states no warning; a retraction without a graph throws.
    init(_ retraction: HealthKitFHIRExporter.Retraction) throws {
        guard let graph = retraction.graph else {
            throw GoldenCaseError.notExported(String(describing: retraction.outcome))
        }
        self.graph = graph
        renderedWarnings = []
        source = HealthKitFHIRExporter.Export.Source(uuid: retraction.deletion.uuid, typeIdentifier: retraction.deletion.sourceType.rawValue)
    }
}


/// One pinned wire shape: a stable name, the event sequence its export takes, and how `HealthKitFHIRExporter` produces it.
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
    /// 2026-08-17T23:30:00Z, in whole seconds: the conversion instant of every case.
    static let conversionInstant = TestEvent.testInstant
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

    /// The export at `index` of the `count` exports one call delivers for `record`, its event numbered `sequence`.
    static func export(
        _ record: HealthKitFHIRExporter.Record,
        sequence: UInt64,
        _ inputs: ExportInputs = ExportInputs(),
        index: Int = 0,
        of count: Int = 1
    ) throws -> GoldenOutput {
        var inputs = inputs
        inputs.sequence = sequence
        let exports = try ExporterFixtures.exports(record, inputs)
        guard exports.count == count else {
            throw GoldenCaseError.unexpectedCompanions(exports.count - 1)
        }
        return try GoldenOutput(exports[index])
    }

    /// The one graph `sample` exports to under `inputs`, its event numbered `sequence`.
    static func export(_ sample: HKSample, sequence: UInt64, _ inputs: ExportInputs = ExportInputs()) throws -> GoldenOutput {
        try export(.sample(sample), sequence: sequence, inputs)
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
    /// An identifier as the system and value its identity rests on.
    private static func key(_ identifier: LosslessJSONValue?) -> String {
        "\(identifier?["system"]?.text ?? "")|\(identifier?["value"]?.text ?? "")"
    }

    /// Where the record the exporter reported disagrees with the graph it reported it for, read from the graph's own
    /// tokens: the reported record is the one the Provenance's source entity names, for a retraction too.
    func reportMismatches(identityScope: OpaqueIdentityScope, repositoryScope: BusinessIdentifier) throws -> [String] {
        let entries: [LosslessJSONValue] = try LosslessJSONValue(parsing: graph.json)["entry"]?.elements ?? []
        let type = try #require(source.sourceType, "a graph reported for the unregistered type \(source.typeIdentifier)")
        let minted = try identityScope.sourceRecord(
            adapterID: HealthKitAssembly.adapter.adapterID,
            sourceType: type.rawValue,
            repositoryScope: repositoryScope,
            nativeRecordID: source.uuid.uuidString.lowercased()
        ).identifier
        let sourceEntities = entries
            .filter { $0["resource"]?["resourceType"]?.text == "Provenance" }
            .flatMap { $0["resource"]?["entity"]?.elements ?? [] }
            .filter { $0["role"]?.text == "source" }
        let named = sourceEntities.map { Self.key($0["what"]?["identifier"]) }
        return named == ["\(minted.identifier.system.rawValue)|\(minted.identifier.value)"] ? [] : ["source"]
    }
}

#endif
