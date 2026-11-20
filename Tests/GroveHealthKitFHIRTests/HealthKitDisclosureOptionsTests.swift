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
import os
import Testing


/// The source and device fact policies, the non-identifying preset, and the native and sync identifier disclosures of
/// ``HealthKitFHIRExporter/Options``.
@Suite("HealthKit disclosure options")
struct HealthKitDisclosureOptionsTests {
    private typealias Options = HealthKitFHIRExporter.Options

    /// The options that narrow what a record states about its origin.
    enum Narrowing: CaseIterable, Sendable {
        case nonIdentifying
        case omitted

        var options: HealthKitFHIRExporter.Options {
            switch self {
            case .nonIdentifying:
                return .nonIdentifying
            case .omitted:
                var options = HealthKitFHIRExporter.Options()
                options.source = .omit
                options.device = .omit
                return options
            }
        }

        /// What the record states under the non-identifying preset and not once the source and the device are omitted.
        var furtherValues: [String] {
            self == .omitted ? ["Device Manufacturer", "Metadata Manufacturer", "Device Model", GoldenFixtures.foreignWriter.bundleIdentifier] : []
        }
    }

    /// One record of each kind of output, each measured on a device and stating every device metadata key.
    enum Output: CaseIterable, Sendable {
        case heartbeatSeries
        case electrocardiogram
        case workout

        /// The identifying facts of the goldens' watch, which records the ECG.
        static let watchValues = ["Apple Watch", "6C4B1D1E-0000-4000-8000-000000000001", "(01)00844588003288"]

        func record() throws -> HealthKitFHIRExporter.Record {
            let metadata = deviceMetadata.merging(GoldenFixtures.timeZoneMetadata) { $1 }
            switch self {
            case .heartbeatSeries:
                var facts = GoldenCase.seriesFacts(uuid: 0xB3, duration: 2)
                facts.device = device
                facts.metadata = metadata
                let series = try StoredSampleFixtures.seriesSample(HKHeartbeatSeriesSample.self, sampleType: HKSeriesType.heartbeat(), facts: facts)
                return .heartbeatSeries(series, beats: ContentCorpusGrid.heartbeats.map(\.heartbeat))
            case .electrocardiogram:
                let symptom = try StoredSampleFixtures.stored(
                    HKCategorySample(
                        type: HKCategoryType(.chestTightnessOrPain),
                        value: HKCategoryValueSeverity.mild.rawValue,
                        start: GoldenFixtures.sampleStart,
                        end: GoldenFixtures.sampleStart.addingTimeInterval(30),
                        device: device,
                        metadata: metadata
                    ),
                    uuid: GoldenFixtures.uuid(0xB5),
                    writer: writer
                )
                let record = try GoldenCase.electrocardiogramRecord(uuid: 0xB4, symptoms: [symptom])
                let stated = (record.electrocardiogram.metadata ?? [:]).merging(deviceMetadata) { $1 }
                _ = try StoredSampleFixtures.withMetadata(record.electrocardiogram, stated)
                return ExporterFixtures.electrocardiogram(record, symptoms: [symptom])
            case .workout:
                let begin = GoldenFixtures.sampleStart
                let lap = HKWorkoutEvent(
                    type: .lap,
                    dateInterval: DateInterval(start: begin, duration: 400),
                    metadata: [HKMetadataKeyDeviceSerialNumber: serial, HKMetadataKeyDeviceName: "Metadata Name"]
                )
                let workout = HKWorkout.fixture(
                    activityType: .running,
                    start: begin,
                    end: begin.addingTimeInterval(3_600),
                    workoutEvents: [lap],
                    device: device,
                    metadata: metadata
                )
                return .sample(try StoredSampleFixtures.stored(workout, uuid: GoldenFixtures.uuid(0xB6), writer: writer))
            }
        }
    }

    private static let writer = GoldenFixtures.foreignWriter
    private static let serial = "SN-0042"
    private static let productionIdentifier = "(11)141231(17)150707(10)A213B1(21)1234"
    private static let device = HKDevice(
        name: "Anna's Watch",
        manufacturer: "Device Manufacturer",
        model: "Device Model",
        hardwareVersion: "hardware-1",
        firmwareVersion: "firmware-2",
        softwareVersion: "software-3",
        localIdentifier: "local-4",
        udiDeviceIdentifier: "device-udi"
    )
    /// Every device key; the name, the manufacturer and the UDI device identifier differ from what ``device`` states.
    private static let deviceMetadata: [String: any Sendable] = [
        HKMetadataKeyDeviceSerialNumber: serial,
        HKMetadataKeyDeviceName: "Metadata Name",
        HKMetadataKeyDeviceManufacturerName: "Metadata Manufacturer",
        HKMetadataKeyUDIDeviceIdentifier: "metadata-udi",
        HKMetadataKeyUDIProductionIdentifier: productionIdentifier
    ]
    /// What the non-identifying device policy keeps on the device.
    private static let identifyingDeviceValues = ["Anna's Watch", "Metadata Name", "local-4", serial, "device-udi", "metadata-udi", productionIdentifier]

    private static func inputs(_ configure: (inout Options) -> Void) -> ExportInputs {
        var inputs = ExportInputs()
        configure(&inputs.options)
        return inputs
    }

    /// A heart rate the foreign application wrote, measured on `device` and stating `metadata`.
    private static func convert(
        _ inputs: ExportInputs,
        device: HKDevice? = device,
        metadata: [String: any Sendable] = deviceMetadata
    ) throws -> HealthKitAssembly.Conversion {
        let stated = metadata.merging(GoldenFixtures.timeZoneMetadata) { $1 }
        return try AssemblyFixtures.conversion(GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xB1), device: device, metadata: stated, writer: writer), inputs)
    }

    private static func recordingDevice(of conversion: HealthKitAssembly.Conversion) -> Device? {
        conversion.record.bundle.entry?.lazy.compactMap { $0.resource?.get(if: Device.self) }.first {
            $0.meta?.profile?.contains(Profile.groveRecordingDevice) == true
        }
    }

    /// The member names of the record's source-revision extension; empty when the source entity states no extension.
    private static func sourceRevisionMembers(of conversion: HealthKitAssembly.Conversion) throws -> [String] {
        let provenance = try #require(conversion.record.bundle.entry?.lazy.compactMap { $0.resource?.get(if: Provenance.self) }.first)
        let entity = try #require(provenance.entity?.first)
        return try (entity.extension ?? []).flatMap { revision in
            try #require(revision.extension).map { $0.url.value?.url.absoluteString ?? "" }
        }
    }

    private static func json(of conversion: HealthKitAssembly.Conversion) -> String {
        String(decoding: conversion.record.json, as: UTF8.self)
    }

    /// The record states nothing as withheld and warns about nothing, and validates when it is read back.
    private static func expectNoOmissionReported(_ conversion: HealthKitAssembly.Conversion, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(conversion.withheldMetadataKeys.isEmpty, sourceLocation: sourceLocation)
        #expect(conversion.warnings.isEmpty, sourceLocation: sourceLocation)
        #expect(throws: Never.self, sourceLocation: sourceLocation) {
            try ExchangeGraph(validating: conversion.record.json, kind: .active)
        }
    }

    /// The source-revision members and the record JSON of a heart rate that a source with `bundleIdentifier` wrote,
    /// without a device, so that nothing but the source revision states the bundle identifier in the clear.
    private static func sourceRevision(
        bundleIdentifier: String,
        _ configure: (inout Options) -> Void
    ) throws -> (members: [String], json: String) {
        let writer = StoredSampleFixtures.Writer(name: "Anna's iPhone", bundleIdentifier: bundleIdentifier, version: "26.1", productType: "iPhone17,1")
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xB7), writer: writer)
        let conversion = try AssemblyFixtures.conversion(sample, Self.inputs(configure))
        Self.expectNoOmissionReported(conversion)
        return (try Self.sourceRevisionMembers(of: conversion), Self.json(of: conversion))
    }

    @Test("By default every source and device fact travels and no sync identifier is disclosed")
    func defaults() throws {
        let options = Options()
        #expect(HealthKitFHIRExporter.SourceFact.allCases.allSatisfy(options.source.includes))
        #expect(HealthKitFHIRExporter.DeviceFact.allCases.allSatisfy(options.device.includes))
        #expect(options.syncIdentifier == .omit)

        let conversion = try Self.convert(ExportInputs())
        #expect(try Self.sourceRevisionMembers(of: conversion) == [
            "sourceName", "sourceBundleIdentifier", "version", "productType", "operatingSystemVersion"
        ])
        let device = try #require(Self.recordingDevice(of: conversion))
        #expect(device.deviceName?.first?.name == "Anna's Watch")
        #expect(device.serialNumber == Self.serial.asFHIRStringPrimitive())
        #expect(device.identifier?.contains { $0.value == "local-4" } == true)
        #expect(conversion.export.metadata?.preservedSampleKeys == 3, "the conflicting name, manufacturer and UDI")
        Self.expectNoOmissionReported(conversion)
    }

    @Test("The non-identifying source policy leaves the source name out of the source-revision extension")
    func nonIdentifyingSource() throws {
        let conversion = try Self.convert(Self.inputs { $0.source = .nonIdentifying })
        #expect(try Self.sourceRevisionMembers(of: conversion) == ["sourceBundleIdentifier", "version", "productType", "operatingSystemVersion"])
        #expect(!Self.json(of: conversion).contains(Self.writer.name))
        Self.expectNoOmissionReported(conversion)
    }

    @Test("The non-identifying source policy omits a bundle identifier HealthKit assigns to one device", arguments: [
        "com.apple.health.94C8E349-0D09-4184-BF6C-AF11692FA465",
        "com.apple.health.94c8e349-0d09-4184-bf6c-af11692fa465"
    ])
    func deviceBundleIdentifierIsOmitted(bundleIdentifier: String) throws {
        let narrowed = try Self.sourceRevision(bundleIdentifier: bundleIdentifier) { $0.source = .nonIdentifying }
        #expect(narrowed.members == ["version", "productType", "operatingSystemVersion"])
        #expect(!narrowed.json.contains(bundleIdentifier))
        #expect(!narrowed.json.localizedCaseInsensitiveContains("94C8E349"), "no shortened or rewritten value")

        let preset = try Self.sourceRevision(bundleIdentifier: bundleIdentifier) { $0 = .nonIdentifying }
        #expect(!preset.json.contains(bundleIdentifier))

        let all = try Self.sourceRevision(bundleIdentifier: bundleIdentifier) { _ in }
        #expect(all.members == ["sourceName", "sourceBundleIdentifier", "version", "productType", "operatingSystemVersion"])
        #expect(all.json.contains(bundleIdentifier))
    }

    @Test("The non-identifying source policy keeps every other bundle identifier", arguments: [
        "com.example.scale",
        "com.apple.health",
        "com.apple.health.",
        "com.apple.health.94C8E349",
        "com.apple.health.94C8E349-0D09-4184-BF6C-AF11692FA465.extra",
        "com.apple.health.94C8E3490-D09-4184-BF6C-AF11692FA465",
        "com.apple.health.94C8E349-0D09-4184-BF6C-AF11692FA46G",
        "com.apple.Health.94C8E349-0D09-4184-BF6C-AF11692FA465",
        "x.com.apple.health.94C8E349-0D09-4184-BF6C-AF11692FA465",
        "com.apple.health.94C8E34\u{FF19}-0D09-4184-BF6C-AF11692FA465",
        "com.apple.health.94C8E349-0D09-4184-BF6C-AF11692FA46\u{E9}"
    ])
    func otherBundleIdentifiersAreKept(bundleIdentifier: String) throws {
        let narrowed = try Self.sourceRevision(bundleIdentifier: bundleIdentifier) { $0.source = .nonIdentifying }
        #expect(narrowed.members == ["sourceBundleIdentifier", "version", "productType", "operatingSystemVersion"])
        #expect(narrowed.json.contains(bundleIdentifier))
    }

    @Test("A custom source policy decides a device's bundle identifier, and an application's travels whenever the extension does")
    func customPolicyDecidesOnlyTheDeviceBundleIdentifier() throws {
        let device = "com.apple.health.94C8E349-0D09-4184-BF6C-AF11692FA465"
        let application = "com.example.scale"
        let omitsDevice: (inout Options) -> Void = { $0.source = .custom { $0 == .deviceBundleIdentifier ? .omit : .include } }
        let keepsVersion: (inout Options) -> Void = { $0.source = .custom { $0 == .version ? .include : .omit } }
        #expect(try !Self.sourceRevision(bundleIdentifier: device, omitsDevice).members.contains("sourceBundleIdentifier"))
        #expect(try Self.sourceRevision(bundleIdentifier: application, omitsDevice).members.contains("sourceBundleIdentifier"))
        // The guide lets a policy withhold the member only in the device form, or with the whole extension.
        #expect(try Self.sourceRevision(bundleIdentifier: device, keepsVersion).members == ["version"])
        #expect(try Self.sourceRevision(bundleIdentifier: application, keepsVersion).members == ["sourceBundleIdentifier", "version"])
        let none = try Self.sourceRevision(bundleIdentifier: application) { $0.source = .custom { _ in .omit } }
        #expect(none.members.isEmpty)
        #expect(!none.json.contains(application))
    }

    @Test("A source policy that omits every fact states no source-revision extension")
    func omittedSource() throws {
        let conversion = try Self.convert(Self.inputs { $0.source = .omit })
        #expect(try Self.sourceRevisionMembers(of: conversion).isEmpty)
        #expect(!Self.json(of: conversion).contains(Self.writer.bundleIdentifier))
        Self.expectNoOmissionReported(conversion)
    }

    @Test("A custom source policy decides each fact")
    func customSource() throws {
        let conversion = try Self.convert(Self.inputs { options in
            options.source = .custom { $0 == .productType ? .include : .omit }
        })
        #expect(try Self.sourceRevisionMembers(of: conversion) == ["sourceBundleIdentifier", "productType"])
        Self.expectNoOmissionReported(conversion)
    }

    @Test("The source policy leaves a stated writer as it is")
    func sourcePolicyLeavesTheWriter() throws {
        var inputs = ExportInputs.applicationWriter
        inputs.options.source = .omit
        let conversion = try Self.convert(inputs)
        let applications = conversion.record.bundle.entry?.compactMap { $0.resource?.get(if: Device.self)?.deviceName?.first?.name.value?.string }
        #expect(applications?.contains(Self.writer.name) == true)
    }

    @Test("The non-identifying device policy omits the name, the local identifier, the serial number and the UDI, whatever supplies them")
    func nonIdentifyingDevice() throws {
        let conversion = try Self.convert(Self.inputs { $0.device = .nonIdentifying })
        let device = try #require(Self.recordingDevice(of: conversion))
        #expect(device.deviceName == nil)
        #expect(device.serialNumber == nil)
        #expect(device.udiCarrier == nil)
        #expect(device.manufacturer == "Device Manufacturer")
        #expect(device.modelNumber == "Device Model")
        #expect(device.version?.count == 3)
        // The unit token is the local identifier, which enters only the keyed identity.
        #expect(Set(device.identifier?.compactMap { try? RoledIdentifier($0).role } ?? []) == [.recordingDevice, .deviceSnapshot])
        #expect(device.identifier?.count == 2)
        let json = Self.json(of: conversion)
        for value in Self.identifyingDeviceValues {
            #expect(!json.contains(value), "\(value)")
        }
        // The omitted device keys are neither preserved as metadata nor counted as excluded metadata.
        #expect(conversion.export.metadata == .init(preservedSampleKeys: 1, unsupportedSampleKeys: 0, excludedSampleKeys: 0))
        #expect(json.contains("Metadata Manufacturer"))
        Self.expectNoOmissionReported(conversion)
    }

    @Test("Device facts that only metadata supplies are omitted, and a Device with no fact left is not stated")
    func nonIdentifyingDeviceFromMetadataAlone() throws {
        let inputs = Self.inputs { $0.device = .nonIdentifying }
        let manufacturerOnly = try Self.convert(inputs, device: nil)
        let device = try #require(Self.recordingDevice(of: manufacturerOnly))
        #expect(device.manufacturer == "Metadata Manufacturer")
        #expect(device.serialNumber == nil && device.deviceName == nil && device.udiCarrier == nil)
        Self.expectNoOmissionReported(manufacturerOnly)

        let identifying = Self.deviceMetadata.filter { $0.key != HKMetadataKeyDeviceManufacturerName }
        let none = try Self.convert(inputs, device: nil, metadata: identifying)
        #expect(Self.recordingDevice(of: none) == nil)
        #expect(none.export.metadata == .init(preservedSampleKeys: 0, unsupportedSampleKeys: 0, excludedSampleKeys: 0))
        Self.expectNoOmissionReported(none)
    }

    @Test("An HKDevice whose only facts the policy omits states no Device, whatever its unit token")
    func deviceWithNoFactLeftIsNotStated() throws {
        let identifying = HKDevice(
            name: "Anna's Watch",
            manufacturer: nil,
            model: nil,
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: "local-4",
            udiDeviceIdentifier: nil
        )
        #expect(try Self.recordingDevice(of: Self.convert(ExportInputs(), device: identifying, metadata: [:])) != nil)
        let conversion = try Self.convert(Self.inputs { $0.device = .nonIdentifying }, device: identifying, metadata: [:])
        #expect(Self.recordingDevice(of: conversion) == nil)
        let json = Self.json(of: conversion)
        #expect(!json.contains("Anna's Watch") && !json.contains("local-4"))
        #expect(!json.contains(GroveIdentifierRole.recordingDevice.rawValue), "no unit identity without a Device")
        Self.expectNoOmissionReported(conversion)
    }

    @Test("A device policy that omits every fact states no recording Device")
    func omittedDevice() throws {
        let conversion = try Self.convert(Self.inputs { $0.device = .omit })
        #expect(Self.recordingDevice(of: conversion) == nil)
        let json = Self.json(of: conversion)
        for value in Self.identifyingDeviceValues + ["Device Manufacturer", "Metadata Manufacturer", "Device Model", "hardware-1"] {
            #expect(!json.contains(value), "\(value)")
        }
        #expect(conversion.export.metadata == .init(preservedSampleKeys: 0, unsupportedSampleKeys: 0, excludedSampleKeys: 0))
        Self.expectNoOmissionReported(conversion)
    }

    @Test("A custom device policy decides each fact")
    func customDevice() throws {
        let conversion = try Self.convert(Self.inputs { options in
            options.device = .custom { $0 == .model || $0 == .serialNumber ? .include : .omit }
        })
        let device = try #require(Self.recordingDevice(of: conversion))
        #expect(device.modelNumber == "Device Model")
        #expect(device.serialNumber == Self.serial.asFHIRStringPrimitive())
        #expect(device.deviceName == nil && device.manufacturer == nil && device.version == nil && device.udiCarrier == nil)
        #expect(!Self.json(of: conversion).contains("local-4"))
        Self.expectNoOmissionReported(conversion)
    }

    @Test("A device policy does not hide a member's device metadata behind a warning")
    func containedDeviceMetadataIsNotWithheld() throws {
        let systolic = try StoredSampleFixtures.withMetadata(
            HKQuantitySample(
                type: HKQuantityType(.bloodPressureSystolic),
                quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: 120),
                start: GoldenFixtures.sampleStart,
                end: GoldenFixtures.sampleStart
            ),
            [HKMetadataKeyDeviceSerialNumber: Self.serial]
        )
        let diastolic = HKQuantitySample(
            type: HKQuantityType(.bloodPressureDiastolic),
            quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: 80),
            start: GoldenFixtures.sampleStart,
            end: GoldenFixtures.sampleStart
        )
        let pressure = HKCorrelation(
            type: HKCorrelationType(.bloodPressure),
            start: GoldenFixtures.sampleStart,
            end: GoldenFixtures.sampleStart,
            objects: [systolic, diastolic],
            metadata: GoldenFixtures.timeZoneMetadata
        )
        #expect(try AssemblyFixtures.conversion(pressure).withheldMetadataKeys == [HKMetadataKeyDeviceSerialNumber])
        let omitted = try AssemblyFixtures.conversion(pressure, Self.inputs { $0.device = .nonIdentifying })
        Self.expectNoOmissionReported(omitted)
    }

    @Test("A custom source or device policy is asked once per fact for each exporter")
    func customPolicyIsResolvedOnce() throws {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let inputs = Self.inputs { options in
            options.device = .custom { _ in
                calls.withLock { $0 += 1 }
                return .include
            }
            options.source = .custom { _ in
                calls.withLock { $0 += 1 }
                return .include
            }
        }
        let facts = HealthKitFHIRExporter.DeviceFact.allCases.count + HealthKitFHIRExporter.SourceFact.allCases.count
        let exporter = try ExporterFixtures.exporter(inputs)
        #expect(calls.withLock { $0 } == facts)
        _ = try exporter.assembly.convert(
            GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xB1), device: Self.device, writer: Self.writer),
            request: HealthKitAssembly.Request(instant: inputs.instant, facts: exporter.producer.facts)
        )
        #expect(calls.withLock { $0 } == facts)
    }

    @Test("A redelivery at the same instant under the disclosure options rebuilds the same bytes")
    func redeliveryIsExact() throws {
        var inputs = ExportInputs()
        inputs.options = .nonIdentifying
        inputs.options.nativeIdentifier = .authorized
        inputs.options.syncIdentifier = .authorized
        let metadata = Self.deviceMetadata.merging(HealthKitMetadataWarningTests.syncPair) { $1 }
        let first = try Self.convert(inputs, metadata: metadata)
        let second = try Self.convert(inputs, metadata: metadata)
        #expect(first.record.json == second.record.json)
        #expect(first.identifiers == second.identifiers)
    }

    @Test("Documents, an ECG with a symptom and a workout with event device metadata keep the omitted facts out", arguments: Output.allCases, Narrowing.allCases)
    func everyOutputKindFollowsThePolicies(output: Output, narrowing: Narrowing) throws {
        var inputs = ExportInputs()
        inputs.options = narrowing.options
        let conversions = try AssemblyFixtures.conversions(output.record(), inputs)
        try #require(conversions.count == (output == .electrocardiogram ? 2 : 1))
        for conversion in conversions {
            let json = Self.json(of: conversion)
            for value in Self.identifyingDeviceValues + Output.watchValues + [Self.writer.name] + narrowing.furtherValues {
                #expect(!json.contains(value), "\(value)")
            }
            #expect((Self.recordingDevice(of: conversion) == nil) == (narrowing == .omitted))
            Self.expectNoOmissionReported(conversion)
        }
    }

    @Test("The non-identifying preset sets the three fact policies and nothing else, and stays a plain value")
    func nonIdentifyingPreset() throws {
        var options = Options.nonIdentifying
        #expect(options.metadata.decision(for: HKMetadataKeyExternalUUID) == .omit)
        #expect(options.metadata.decision(for: "com.example.note") == .include)
        #expect(HealthKitFHIRExporter.SourceFact.allCases.filter { !options.source.includes($0) } == [.name, .deviceBundleIdentifier])
        #expect(HealthKitFHIRExporter.DeviceFact.allCases.filter { !options.device.includes($0) } == [
            .name, .localIdentifier, .udiDeviceIdentifier, .udiProductionIdentifier, .serialNumber
        ])
        #expect(options.nativeIdentifier == .omit)
        #expect(options.syncIdentifier == .omit)
        #expect(options.route == .omit)

        var inputs = ExportInputs()
        inputs.options = options
        let conversion = try Self.convert(inputs, metadata: Self.deviceMetadata.merging([HKMetadataKeyExternalUUID: "external-7"]) { $1 })
        let json = Self.json(of: conversion)
        for value in Self.identifyingDeviceValues + [Self.writer.name, "external-7"] {
            #expect(!json.contains(value), "\(value)")
        }
        #expect(conversion.export.metadata == .init(preservedSampleKeys: 1, unsupportedSampleKeys: 0, excludedSampleKeys: 1))
        Self.expectNoOmissionReported(conversion)

        options.device = .all
        inputs.options = options
        #expect(try Self.recordingDevice(of: Self.convert(inputs))?.serialNumber == Self.serial.asFHIRStringPrimitive())
    }
}

#endif
