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
    private let converter = HealthKitConverter()
    private let timestamp = Date(timeIntervalSince1970: 1_787_148_600)

    private func context(
        subjectID: String = "1a2b3c",
        eventOffset: TimeInterval = 0,
        stableUnitToken: String? = nil,
        sourceActor: HealthKitSourceActor = .application
    ) -> HealthKitConversionContext {
        HealthKitConversionContext(
            subject: .testLogicalReference(resourceType: .patient, value: subjectID),
            converter: HealthKitApplication(
                name: "Example Study",
                bundleIdentifier: "org.grovealliance.example-study",
                version: "2.0.0",
                build: "42"
            ),
            graphIdentifierSystem: "https://study.example.org/fhir/identifiers/mobile-graph",
            sourceActor: sourceActor,
            conversionInstant: timestamp.addingTimeInterval(eventOffset),
            recordingDeviceStableUnitToken: stableUnitToken
        )
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
        let conversion = try converter.convert(sample(watch()), context: context())

        #expect(conversion.recordingDevice == nil)
        #expect(conversion.graphIdentifiers.recordingDeviceSnapshot == nil)
        #expect(conversion.observation.device == nil)
    }

    @Test("The converting application has one clear typed bundle id and one opaque snapshot")
    func converterApplicationIdentity() throws {
        let conversion = try converter.convert(sample(watch()), context: context())
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
        #expect(try BusinessIdentifier(identifiers[0]).role == .deviceSnapshot)
        #expect(bundleIdentifier.value?.value?.string == "org.grovealliance.example-study")
        #expect(typeCodings?.count == 1)
        #expect(typeCodings?.first?.code?.value?.string == HealthKitContract.appleBundleIdentifierTypeCode)
    }

    @Test("A governed stable token emits stable-unit and immutable-snapshot identifiers")
    func emitsBothTypedIdentifiers() throws {
        let conversion = try converter.convert(
            sample(watch()),
            context: context(stableUnitToken: "watch-unit-7")
        )
        let device = try #require(conversion.recordingDevice)
        let identifiers = try #require(device.identifier).map { try BusinessIdentifier($0) }

        #expect(identifiers.map(\.role) == [.deviceSnapshot, .recordingDevice])
        #expect(identifiers[0] == conversion.graphIdentifiers.recordingDeviceSnapshot)
        #expect(device.meta?.profile?.contains(Profile.groveRecordingDevice) == true)
    }

    @Test("Firmware changes create a new snapshot without changing the physical-unit identity")
    func firmwareChangesDoNotMutateHistory() throws {
        let before = try converter.convert(
            sample(watch(firmware: "11.2")),
            context: context(eventOffset: 0, stableUnitToken: "watch-unit-7")
        )
        let after = try converter.convert(
            sample(watch(firmware: "11.3"), offset: 600),
            context: context(eventOffset: 1, stableUnitToken: "watch-unit-7")
        )
        let beforeIdentifiers = try #require(before.recordingDevice?.identifier).map { try BusinessIdentifier($0) }
        let afterIdentifiers = try #require(after.recordingDevice?.identifier).map { try BusinessIdentifier($0) }

        #expect(beforeIdentifiers[1] == afterIdentifiers[1])
        #expect(beforeIdentifiers[0] != afterIdentifiers[0])
        #expect(before.recordingDevice?.version != after.recordingDevice?.version)
    }

    @Test("Stable physical identity is scoped to the subject")
    func stableIdentityIsSubjectScoped() throws {
        let mine = try converter.convert(
            sample(watch()),
            context: context(subjectID: "1a2b3c", eventOffset: 0, stableUnitToken: "watch-unit-7")
        )
        let yours = try converter.convert(
            sample(watch()),
            context: context(subjectID: "9z8y7x", eventOffset: 1, stableUnitToken: "watch-unit-7")
        )
        let mineIdentifiers = try #require(mine.recordingDevice?.identifier).map { try BusinessIdentifier($0) }
        let yoursIdentifiers = try #require(yours.recordingDevice?.identifier).map { try BusinessIdentifier($0) }

        #expect(mineIdentifiers[1] != yoursIdentifiers[1])
    }

    @Test("A HealthKit local identifier can supply the stable source token")
    func localIdentifierSuppliesStableEvidence() throws {
        let conversion = try converter.convert(
            sample(watch(localIdentifier: "healthkit-device-42")),
            context: context()
        )

        #expect(conversion.recordingDevice != nil)
        #expect(conversion.graphIdentifiers.recordingDeviceSnapshot != nil)
    }

    @Test("A device source reuses the dual-identity recording snapshot as its Provenance author")
    func deviceSourceReusesRecordingDevice() throws {
        let conversion = try converter.convert(
            sample(watch()),
            context: context(stableUnitToken: "watch-unit-7", sourceActor: .device)
        )
        let author = try #require(conversion.provenance.entity?.first?.agent?.first)

        #expect(conversion.sourceAuthor == nil)
        #expect(author.who.reference == conversion.observation.device?.reference)
        #expect(conversion.graphIdentifiers.sourceAuthorSnapshot == nil)
        #expect(conversion.graphIdentifiers.recordingDeviceSnapshot != nil)
    }
}

#endif
