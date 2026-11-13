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


/// Every fact `HKDevice` and the device metadata keys supply, as the HealthKit guide's device rules map them.
@Suite("HealthKit recording Device facts")
struct HealthKitDeviceFactsTests {
    private static let start = Date(timeIntervalSince1970: 1_787_148_600)
    private static let serial = "SN-0042"
    private static let productionIdentifier = "(11)141231(17)150707(10)A213B1(21)1234"
    /// Every device key, each with a value no `HKDevice` below states.
    private static let deviceMetadata: [String: any Sendable] = [
        HKMetadataKeyDeviceSerialNumber: serial,
        HKMetadataKeyDeviceName: "Metadata Name",
        HKMetadataKeyDeviceManufacturerName: "Metadata Manufacturer",
        HKMetadataKeyUDIDeviceIdentifier: "metadata-udi",
        HKMetadataKeyUDIProductionIdentifier: productionIdentifier
    ]

    private static let everyFact = HKDevice(
        name: "Device Name",
        manufacturer: "Device Manufacturer",
        model: "Device Model",
        hardwareVersion: "hardware-1",
        firmwareVersion: "firmware-2",
        softwareVersion: "software-3",
        localIdentifier: "local-4",
        udiDeviceIdentifier: "device-udi"
    )
    /// HealthKit requires an `HKDevice` to state at least one fact.
    private static let modelOnly = HKDevice(
        name: nil,
        manufacturer: nil,
        model: "Device Model",
        hardwareVersion: nil,
        firmwareVersion: nil,
        softwareVersion: nil,
        localIdentifier: nil,
        udiDeviceIdentifier: nil
    )

    private static func heartRate(_ device: HKDevice?, metadata: [String: any Sendable] = [:]) throws -> HKQuantitySample {
        let stated = metadata.merging(GoldenFixtures.timeZoneMetadata) { $1 }
        return try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xC1), device: device, metadata: stated)
    }

    private static func versions(of device: Device) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (device.version ?? []).compactMap { version in
            guard let code = version.type?.coding?.first?.code?.value?.string, let value = version.value.value?.string else {
                return nil
            }
            return (code, value)
        })
    }

    private static func name(of device: Device) -> DeviceDeviceName? {
        device.deviceName?.first
    }

    @Test("Every HKDevice property reaches its element")
    func everyHKDevicePropertyTravels() async throws {
        let conversion = try await ExporterFixtures.export(try Self.heartRate(Self.everyFact))
        let device = try #require(conversion.recordingDevice)

        #expect(Self.name(of: device)?.name == "Device Name")
        #expect(Self.name(of: device)?.type.value == .userFriendlyName)
        #expect(device.deviceName?.count == 1)
        #expect(device.manufacturer == "Device Manufacturer")
        #expect(device.modelNumber == "Device Model")
        #expect(Self.versions(of: device) == ["531974": "hardware-1", "531976": "firmware-2", "531975": "software-3"])
        #expect(device.identifier?.contains { $0.value == "local-4" } == true)
        #expect(device.udiCarrier?.map(\.deviceIdentifier) == ["device-udi"])
        #expect(device.serialNumber == nil)
        #expect(conversion.primary.warnings.isEmpty)
    }

    @Test("A device metadata key fills what HKDevice leaves absent")
    func metadataFillsAbsentFacts() async throws {
        let conversion = try await ExporterFixtures.export(try Self.heartRate(Self.modelOnly, metadata: Self.deviceMetadata))
        let device = try #require(conversion.recordingDevice)

        #expect(Self.name(of: device)?.name == "Metadata Name")
        #expect(device.manufacturer == "Metadata Manufacturer")
        #expect(device.udiCarrier?.first?.deviceIdentifier == "metadata-udi")
        #expect(device.serialNumber == "SN-0042")
        #expect(conversion.primary.warnings.isEmpty, "every key is carried")
    }

    @Test("An HKDevice property wins for Device facts while the raw metadata remains preserved")
    func hkDeviceWins() async throws {
        let sample = try Self.heartRate(Self.everyFact, metadata: Self.deviceMetadata)
        let conversion = try await ExporterFixtures.export(sample)
        let device = try #require(conversion.recordingDevice)

        #expect(Self.name(of: device)?.name == "Device Name")
        #expect(device.manufacturer == "Device Manufacturer")
        #expect(device.udiCarrier?.first?.deviceIdentifier == "device-udi")
        #expect(device.serialNumber == "SN-0042", "the serial number has no HKDevice property")
        let assembled = try AssemblyFixtures.conversion(sample)
        #expect(assembled.withheldMetadataKeys.isEmpty)
        #expect(assembled.export.metadata?.preservedSampleKeys == Self.deviceMetadata.count + 1)
        #expect(conversion.primary.warnings.isEmpty)
    }

    @Test("A key stating what its HKDevice property states is carried")
    func equalValuesAreCarried() async throws {
        let sample = try Self.heartRate(Self.everyFact, metadata: [
            HKMetadataKeyDeviceName: "Device Name",
            HKMetadataKeyDeviceManufacturerName: "Device Manufacturer",
            HKMetadataKeyUDIDeviceIdentifier: "device-udi"
        ])
        #expect(try AssemblyFixtures.conversion(sample).withheldMetadataKeys.isEmpty)
    }

    @Test("The UDI production identifier travels in its extension on udiCarrier, with or without a device identifier")
    func productionIdentifierExtension() async throws {
        for device in [Self.modelOnly, Self.everyFact] {
            let sample = try Self.heartRate(device, metadata: [HKMetadataKeyUDIProductionIdentifier: Self.productionIdentifier])
            let conversion = try await ExporterFixtures.export(sample)
            let carrier = try #require(conversion.recordingDevice?.udiCarrier?.first)
            #expect(carrier.extension?.map(\.url) == [Canonicals.udiProductionIdentifier])
            #expect(carrier.extension?.first?.value == .string(Self.productionIdentifier.asFHIRStringPrimitive()))
        }
    }

    @Test("Device metadata remains available even when HealthKit supplies no HKDevice")
    func noDevicePreservesMetadata() async throws {
        let sample = try Self.heartRate(nil, metadata: Self.deviceMetadata)
        let assembled = try AssemblyFixtures.conversion(sample)
        #expect(assembled.withheldMetadataKeys.isEmpty)
        #expect(assembled.export.metadata?.preservedSampleKeys == Self.deviceMetadata.count + 1)
        #expect(assembled.warnings.isEmpty)
    }

    @Test("Uninterpretable device facts remain raw metadata without populating the Device")
    func unreadableValuesRemainMetadata() async throws {
        let sample = try StoredSampleFixtures.withMetadata(Self.heartRate(Self.modelOnly), [
            HKMetadataKeyTimeZone: GoldenFixtures.timeZone,
            HKMetadataKeyDeviceSerialNumber: 42,
            HKMetadataKeyDeviceName: "   "
        ])
        let assembled = try AssemblyFixtures.conversion(sample)
        let conversion = try await ExporterFixtures.export(sample)
        #expect(assembled.withheldMetadataKeys.isEmpty)
        #expect(assembled.export.metadata?.preservedSampleKeys == 3)
        #expect(conversion.recordingDevice?.serialNumber == nil)
        #expect(conversion.recordingDevice?.deviceName == nil)
    }

    @Test("Documents preserve metadata while their Device states HKDevice alone")
    func documentsPreserveDeviceMetadata() async throws {
        var facts = GoldenCase.seriesFacts(uuid: 0xC2, duration: 2)
        facts.device = Self.everyFact
        facts.metadata = Self.deviceMetadata.merging([HKMetadataKeyDeviceName: "Device Name"]) { $1 }
        let series = try StoredSampleFixtures.seriesSample(HKHeartbeatSeriesSample.self, sampleType: HKSeriesType.heartbeat(), facts: facts)
        let beats = [HealthKitFHIRExporter.Record.Heartbeat(timeSinceSeriesStart: 0, precededByGap: false)]
        let assembled = try #require(try AssemblyFixtures.conversions(.heartbeatSeries(series, beats: beats)).first)
        let devices = assembled.record.bundle.entry?.compactMap { $0.resource?.get(if: Device.self) } ?? []
        let device = try #require(devices.first { $0.meta?.profile?.contains(Profile.groveRecordingDevice) == true })

        #expect(device.serialNumber == nil)
        #expect(device.udiCarrier?.first?.extension == nil)
        #expect(assembled.withheldMetadataKeys.isEmpty)
        #expect(assembled.export.metadata?.preservedSampleKeys == Self.deviceMetadata.count)
    }

    @Test("Every device fact is content: a changed one is a new snapshot and a new record version")
    func everyFactIsContent() async throws {
        let base = try await ExporterFixtures.export(try Self.heartRate(Self.modelOnly))
        for (key, value) in Self.deviceMetadata {
            let changed = try await ExporterFixtures.export(try Self.heartRate(Self.modelOnly, metadata: [key: value]))
            #expect(changed.identifiers.recordingDeviceSnapshot != base.identifiers.recordingDeviceSnapshot, "\(key)")
            #expect(changed.record.version != base.record.version, "\(key)")
            #expect(changed.record.sourceRecord == base.record.sourceRecord, "\(key)")
        }
    }
}

#endif
