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


@Suite("HealthKit recording Device identity")
struct HealthKitFHIRDeviceIdentityTests {
    private let timestamp = Date(timeIntervalSince1970: 1_787_148_600)

    /// One export's inputs; events a test tells apart take distinct sequences, as distinct conversion instants did.
    private func inputs(
        subjectID: String = "1a2b3c",
        eventOffset: UInt64 = 0,
        stableUnitToken: String? = nil,
        writer: HealthKitFHIRExporter.WriterPolicy = .omit
    ) -> ExportInputs {
        var inputs = ExportInputs()
        inputs.subject = .logical(.test(.patient, subjectID))
        inputs.converter = ApplicationDevice.test(
            name: "Example Study",
            bundleIdentifier: "org.grovealliance.example-study",
            version: "2.0.0",
            build: "42"
        )
        inputs.graphIdentifierSystem = "https://study.example.org/fhir/identifiers/mobile-graph"
        inputs.instant = timestamp
        inputs.sequence = 1 + eventOffset
        inputs.options.writer = writer
        if let stableUnitToken {
            inputs.options.recordingDevice = .custom(FixedTokenRecordingDeviceResolver(token: stableUnitToken))
        }
        return inputs
    }

    private func watch(
        firmware: String = "11.2",
        localIdentifier: String? = nil
    ) -> HKDevice {
        HKDevice(
            name: "Apple Watch",
            manufacturer: "Apple Inc.",
            model: "Watch",
            hardwareVersion: "Watch7,12",
            firmwareVersion: firmware,
            softwareVersion: "26.0",
            localIdentifier: localIdentifier,
            udiDeviceIdentifier: nil
        )
    }

    private func sample(_ device: HKDevice, offset: TimeInterval = 0) -> HKQuantitySample {
        HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: 62),
            start: timestamp.addingTimeInterval(offset),
            end: timestamp.addingTimeInterval(offset),
            device: device,
            metadata: nil
        )
    }

    @Test("Model and version facts alone never claim a physical Device instance")
    func unknownPhysicalUnitIsOmitted() throws {
        let conversion = try ExporterFixtures.export(sample(watch()), inputs())

        #expect(conversion.recordingDevice == nil)
        #expect(conversion.identifiers.recordingDeviceSnapshot == nil)
        #expect(conversion.observation.device == nil)
    }

    @Test("The converting application has one clear typed bundle id and one opaque snapshot")
    func converterApplicationIdentity() throws {
        let conversion = try ExporterFixtures.export(sample(watch()), inputs())
        let application = conversion.converterApplication
        let identifiers = try #require(application.identifier)
        let bundleIdentifier = try #require(identifiers.first(where: {
            $0.system == HealthKitContract.appleBundleIdentifierSystem
        }))
        let typeCodings = bundleIdentifier.type?.coding?.filter {
            $0.system == HealthKitContract.appleBundleIdentifierTypeSystem
        }

        #expect(application.meta?.profile == [HealthKitContract.applicationDeviceProfile])
        #expect(identifiers.count == 2)
        #expect(try RoledIdentifier(identifiers[0]).role == .deviceSnapshot)
        #expect(bundleIdentifier.value?.value?.string == "org.grovealliance.example-study")
        #expect(typeCodings?.count == 1)
        #expect(typeCodings?.first?.code?.value?.string == HealthKitContract.appleBundleIdentifierTypeCode)
    }

    @Test("A governed stable token emits stable-unit and immutable-snapshot identifiers")
    func emitsBothTypedIdentifiers() throws {
        let conversion = try ExporterFixtures.export(
            sample(watch()),
            inputs(stableUnitToken: "watch-unit-7")
        )
        let device = try #require(conversion.recordingDevice)
        let identifiers = try #require(device.identifier).map { try RoledIdentifier($0) }

        #expect(identifiers.map(\.role) == [.deviceSnapshot, .recordingDevice])
        #expect(identifiers[0] == conversion.identifiers.recordingDeviceSnapshot)
        #expect(device.meta?.profile?.contains(Profile.groveRecordingDevice) == true)
    }

    @Test("Firmware changes create a new snapshot without changing the physical-unit identity")
    func firmwareChangesDoNotMutateHistory() throws {
        let before = try ExporterFixtures.export(
            sample(watch(firmware: "11.2")),
            inputs(eventOffset: 0, stableUnitToken: "watch-unit-7")
        )
        let after = try ExporterFixtures.export(
            sample(watch(firmware: "11.3"), offset: 600),
            inputs(eventOffset: 1, stableUnitToken: "watch-unit-7")
        )
        let beforeIdentifiers = try #require(before.recordingDevice?.identifier).map { try RoledIdentifier($0) }
        let afterIdentifiers = try #require(after.recordingDevice?.identifier).map { try RoledIdentifier($0) }

        #expect(beforeIdentifiers[1] == afterIdentifiers[1])
        #expect(beforeIdentifiers[0] != afterIdentifiers[0])
        #expect(before.recordingDevice?.version != after.recordingDevice?.version)
    }

    @Test("Stable physical identity is scoped to the subject")
    func stableIdentityIsSubjectScoped() throws {
        let mine = try ExporterFixtures.export(
            sample(watch()),
            inputs(subjectID: "1a2b3c", eventOffset: 0, stableUnitToken: "watch-unit-7")
        )
        let yours = try ExporterFixtures.export(
            sample(watch()),
            inputs(subjectID: "9z8y7x", eventOffset: 1, stableUnitToken: "watch-unit-7")
        )
        let mineIdentifiers = try #require(mine.recordingDevice?.identifier).map { try RoledIdentifier($0) }
        let yoursIdentifiers = try #require(yours.recordingDevice?.identifier).map { try RoledIdentifier($0) }

        #expect(mineIdentifiers[1] != yoursIdentifiers[1])
    }

    @Test("A HealthKit local identifier can supply the stable source token")
    func localIdentifierSuppliesStableEvidence() throws {
        let conversion = try ExporterFixtures.export(
            sample(watch(localIdentifier: "healthkit-device-42")),
            inputs()
        )

        #expect(conversion.recordingDevice != nil)
        #expect(conversion.identifiers.recordingDeviceSnapshot != nil)
    }

    @Test("An unclassified source keeps the recording Device its HKDevice names, and the Provenance names no author")
    func unclassifiedSourceKeepsTheRecordingDevice() throws {
        let attributed = try StoredSampleFixtures.stored(sample(watch()), uuid: GoldenFixtures.uuid(0xB7), writer: GoldenFixtures.foreignWriter)
        let conversion = try ExporterFixtures.export(attributed, inputs(stableUnitToken: "watch-unit-7", writer: .omit))
        let recordingDevice = try #require(conversion.identifiers.recordingDeviceSnapshot)

        #expect(conversion.writer == nil)
        #expect(conversion.identifiers.writerSnapshot == nil)
        #expect(conversion.provenance.entity?.first?.agent == nil)
        #expect(conversion.observation.device?.reference?.value?.string == (try recordingDevice.fullURLString))
    }
}

#endif
