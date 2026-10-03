//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


/// What one case pins: the graph the old API emitted and, in order, what it reported losing.
struct GoldenOutput: Sendable {
    let graph: ExchangeGraph
    let warnings: [HealthKitConversionWarning]

    /// Each warning as the outline spells it: the registry code, then the field, device name or keys it names.
    var renderedWarnings: [String] {
        warnings.map { warning in
            switch warning {
            case .recordingDeviceOmitted(let deviceName):
                "\(warning.diagnostic.code)(\(deviceName ?? ""))"
            case .sourceOffsetUnavailable(let field):
                "\(warning.diagnostic.code)@\(field)"
            case .unmodeledMetadataWithheld(let keys):
                "\(warning.diagnostic.code)(\(keys.joined(separator: ",")))"
            }
        }
    }

    init(_ conversion: HealthKitConversion) {
        graph = conversion.graph
        warnings = conversion.warnings
    }

    init(_ retraction: RetractionEvent) {
        graph = retraction.graph
        warnings = []
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

    /// The primary graph of `sample` under the old public entry point, with what the conversion reported losing.
    static func convert(_ sample: HKSample, sequence: UInt64, _ inputs: Inputs = Inputs()) throws -> GoldenOutput {
        GoldenOutput(try HealthKitConverter().convert(sample, context: context(sequence: sequence, inputs)).primary)
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

#endif
