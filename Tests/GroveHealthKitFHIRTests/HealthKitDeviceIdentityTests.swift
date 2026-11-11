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


@Suite("HealthKit recording Device identity")
struct HealthKitFHIRDeviceIdentityTests {
    private let timestamp = Date(timeIntervalSince1970: 1_787_148_600)

    private func inputs(
        subjectID: String = "1a2b3c",
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
        inputs.options.writer = writer
        if let stableUnitToken {
            inputs.options.unitToken = .custom { _, _ in stableUnitToken }
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

    /// A heart rate `writer` stored, which `device` measured.
    private func sample(
        _ device: HKDevice,
        offset: TimeInterval = 0,
        writer: StoredSampleFixtures.Writer = GoldenFixtures.foreignWriter
    ) throws -> HKQuantitySample {
        let sample = HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: 62),
            start: timestamp.addingTimeInterval(offset),
            end: timestamp.addingTimeInterval(offset),
            device: device,
            metadata: nil
        )
        return try StoredSampleFixtures.stored(sample, uuid: GoldenFixtures.uuid(0xB0), writer: writer)
    }

    /// The typed identities of `device`, leaving out its clear local identifier.
    private func typedIdentities(of device: Device?) throws -> [RoledIdentifier] {
        try #require(device?.identifier).compactMap { try? RoledIdentifier($0) }
    }

    @Test("A Device without a unit token is still emitted and referenced, and proves no physical unit")
    func deviceWithoutATokenIsEmitted() async throws {
        let conversion = try await ExporterFixtures.export(sample(watch()), inputs())
        let snapshot = try #require(conversion.identifiers.recordingDeviceSnapshot)

        #expect(try typedIdentities(of: conversion.recordingDevice).map(\.role) == [.deviceSnapshot])
        #expect(conversion.observation.device?.reference?.value?.string == (try snapshot.fullURLString))
    }

    @Test("A sample without an HKDevice names no recording Device")
    func noDeviceNamesNone() async throws {
        let bare = HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: 62),
            start: timestamp,
            end: timestamp
        )
        let conversion = try await ExporterFixtures.export(bare, inputs())

        #expect(conversion.recordingDevice == nil)
        #expect(conversion.observation.device == nil)
    }

    @Test("The converting application has one clear typed bundle id and one opaque snapshot")
    func converterApplicationIdentity() async throws {
        let conversion = try await ExporterFixtures.export(sample(watch()), inputs())
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
    func emitsBothTypedIdentifiers() async throws {
        let conversion = try await ExporterFixtures.export(
            sample(watch()),
            inputs(stableUnitToken: "watch-unit-7")
        )
        let device = try #require(conversion.recordingDevice)
        let identifiers = try typedIdentities(of: device)

        #expect(identifiers.map(\.role) == [.deviceSnapshot, .recordingDevice])
        #expect(identifiers[0] == conversion.identifiers.recordingDeviceSnapshot)
        #expect(device.meta?.profile?.contains(Profile.groveRecordingDevice) == true)
    }

    @Test("Firmware changes create a new snapshot without changing the physical-unit identity")
    func firmwareChangesDoNotMutateHistory() async throws {
        let before = try await ExporterFixtures.export(
            sample(watch(firmware: "11.2")),
            inputs(stableUnitToken: "watch-unit-7")
        )
        let after = try await ExporterFixtures.export(
            sample(watch(firmware: "11.3"), offset: 600),
            inputs(stableUnitToken: "watch-unit-7")
        )
        let beforeIdentifiers = try typedIdentities(of: before.recordingDevice)
        let afterIdentifiers = try typedIdentities(of: after.recordingDevice)

        #expect(beforeIdentifiers[1] == afterIdentifiers[1])
        #expect(beforeIdentifiers[0] != afterIdentifiers[0])
        #expect(before.recordingDevice?.version != after.recordingDevice?.version)
    }

    @Test("Equal device content is one snapshot in every record")
    func equalContentIsOneSnapshot() async throws {
        let first = try await ExporterFixtures.export(sample(watch()), inputs())
        let second = try await ExporterFixtures.export(sample(watch(), offset: 600), inputs())

        #expect(first.identifiers.recordingDeviceSnapshot == second.identifiers.recordingDeviceSnapshot)
    }

    @Test("Stable physical identity is scoped to the subject")
    func stableIdentityIsSubjectScoped() async throws {
        let mine = try await ExporterFixtures.export(
            sample(watch()),
            inputs(subjectID: "1a2b3c", stableUnitToken: "watch-unit-7")
        )
        let yours = try await ExporterFixtures.export(
            sample(watch()),
            inputs(subjectID: "9z8y7x", stableUnitToken: "watch-unit-7")
        )

        #expect(try typedIdentities(of: mine.recordingDevice)[1] != typedIdentities(of: yours.recordingDevice)[1])
    }

    @Test("The same token from two writers names two units")
    func stableIdentityIsScopedToTheWriter() async throws {
        let device = watch(localIdentifier: "shared-local-identifier")
        let firstConversion = try await ExporterFixtures.export(sample(device), inputs())
        let secondConversion = try await ExporterFixtures.export(sample(device, writer: GoldenFixtures.selfWriter(revisionVersion: "1")), inputs())

        #expect(try typedIdentities(of: firstConversion.recordingDevice)[1] != typedIdentities(of: secondConversion.recordingDevice)[1])
    }

    @Test("A source without a bundle identifier names hardware, not a unit: a token needs the writer that assigned it")
    func aTokenNeedsItsWriter() async throws {
        let blank = StoredSampleFixtures.Writer(name: "Unknown", bundleIdentifier: "", version: nil, productType: nil)
        let conversion = try await ExporterFixtures.export(sample(watch(localIdentifier: "healthkit-device-42"), writer: blank), inputs())

        #expect(try typedIdentities(of: conversion.recordingDevice).map(\.role) == [.deviceSnapshot])
    }

    @Test("HKDevice.localIdentifier is the default token, under every policy a clear identifier of the Device")
    func localIdentifierIsTokenAndFact() async throws {
        let device = watch(localIdentifier: "healthkit-device-42")
        func clearIdentifier(_ conversion: ExportedRecord) throws -> Identifier? {
            try #require(conversion.recordingDevice?.identifier).first { $0.type?.coding?.first?.code == "device-local-identifier" }
        }
        let byDefault = try await ExporterFixtures.export(sample(device), inputs())
        #expect(try typedIdentities(of: byDefault.recordingDevice).map(\.role) == [.deviceSnapshot, .recordingDevice])

        var withoutToken = inputs()
        withoutToken.options.unitToken = .none
        let withheld = try await ExporterFixtures.export(sample(device), withoutToken)
        #expect(try typedIdentities(of: withheld.recordingDevice).map(\.role) == [.deviceSnapshot])

        for conversion in [byDefault, withheld] {
            let identifier = try #require(try clearIdentifier(conversion))
            #expect(identifier.value == "healthkit-device-42")
            #expect(identifier.type?.coding?.first?.system == Canonicals.groveDeviceIdentifierType)
            #expect(identifier.system?.value?.url.absoluteString == withoutToken.base.identityScope.systems.deviceLocalIdentifier.rawValue)
        }
    }

    @Test("A custom token sees the HKDevice and the HKSource, and a blank answer states no unit")
    func customTokenSeesItsInputs() async throws {
        let stored = try sample(watch())
        var named = inputs()
        named.options.unitToken = .custom { device, source in "\(source.bundleIdentifier)/\(device.model ?? "")" }
        let reference = try await ExporterFixtures.export(stored, inputs(stableUnitToken: "org.example.writer/Watch"))
        let conversion = try await ExporterFixtures.export(stored, named)
        #expect(try typedIdentities(of: conversion.recordingDevice) == typedIdentities(of: reference.recordingDevice))

        var blank = inputs()
        blank.options.unitToken = .custom { _, _ in "  " }
        let unnamed = try await ExporterFixtures.export(stored, blank)
        #expect(try typedIdentities(of: unnamed.recordingDevice).map(\.role) == [.deviceSnapshot])
    }

    @Test("An unclassified source keeps the recording Device its HKDevice names, and the Provenance names no author")
    func unclassifiedSourceKeepsTheRecordingDevice() async throws {
        let conversion = try await ExporterFixtures.export(sample(watch()), inputs(stableUnitToken: "watch-unit-7", writer: .omit))
        let recordingDevice = try #require(conversion.identifiers.recordingDeviceSnapshot)

        #expect(conversion.writer == nil)
        #expect(conversion.identifiers.writerSnapshot == nil)
        #expect(conversion.provenance.entity?.first?.agent == nil)
        #expect(conversion.observation.device?.reference?.value?.string == (try recordingDevice.fullURLString))
    }

    @Test("Validation refuses an Observation.device that resolves to a snapshot other than the recording Device")
    func observationDeviceResolvesOnlyToTheRecordingDevice() async throws {
        let conversion = try await ExporterFixtures.export(sample(watch()), inputs(stableUnitToken: "watch-unit-7"))
        let graph = conversion.graph
        let entries = try #require(graph.bundle.entry)
        let index = try #require(entries.firstIndex { $0.resource?.get(if: Observation.self) != nil })
        for snapshot in [conversion.identifiers.applicationSnapshot, conversion.identifiers.hostSnapshot] {
            var observation = conversion.observation
            observation.device = Reference(reference: try snapshot.fullURLString.asFHIRStringPrimitive())
            var bundle = graph.bundle
            bundle.entry?[index].resource = ResourceProxy(with: observation)
            #expect(throws: ExchangeGraphError.ruleViolation(.mobileExchangeReferenceTargetType)) {
                try ExchangeGraph(kind: .active, bundle: bundle)
            }
        }
        // The recording Device the export linked revalidates.
        _ = try ExchangeGraph(kind: .active, bundle: graph.bundle)
    }
}

#endif
