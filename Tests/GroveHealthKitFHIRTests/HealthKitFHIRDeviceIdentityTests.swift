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


/// One physical recorder should be stored once per configuration, not once per sample — but only
/// for a deployment that opted in, because a shared device identity is not an exchange default.
@Suite
struct HealthKitFHIRDeviceIdentityTests {
    private let converter = HealthKitFHIRConverter()
    private let timestamp = Date(timeIntervalSince1970: 1_787_148_600)
    private let scope = "1f5c58aa-6ec6-4e79-a682-829a9debd3f5"

    private func context(deviceIdentityScope: String? = nil) -> HealthKitFHIRConversionContext {
        HealthKitFHIRConversionContext(
            subject: Reference(reference: "Patient/example"),
            converter: HealthKitFHIRApplication(
                name: "Example Study",
                bundleIdentifier: "org.grovealliance.example-study",
                version: "2.0.0 (42)"
            ),
            graphIdentifierSystem: "https://study.example.org/fhir/identifiers/mobile-graph",
            conversionInstant: timestamp,
            deviceIdentityScope: deviceIdentityScope
        )
    }

    private func watch(firmware: String = "11.2", model: String? = "Watch") -> HKDevice {
        HKDevice(
            name: "Apple Watch",
            manufacturer: "Apple Inc.",
            model: model,
            hardwareVersion: "Watch7,12",
            firmwareVersion: firmware,
            softwareVersion: "26.0",
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        )
    }

    private func sample(_ device: HKDevice, offset: TimeInterval) -> HKQuantitySample {
        HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: 62),
            start: timestamp.addingTimeInterval(offset),
            end: timestamp.addingTimeInterval(offset),
            device: device,
            metadata: nil
        )
    }

    private func deviceIdentifier(_ conversion: HealthKitFHIRConversion) throws -> String {
        let device = try #require(conversion.recordingDevice)
        let identifier = try #require(device.identifier?.first)
        return try #require(identifier.value?.value?.string)
    }

    @Test("Without an opted-in scope every sample keeps its own recording device")
    func perSampleIdentityIsTheDefault() throws {
        let device = watch()
        let first = try converter.convert(sample(device, offset: 0), context: context())
        let second = try converter.convert(sample(device, offset: 600), context: context())
        // The resource carries no identifier by default, so identity is compared on the graph node.
        #expect(first.graphIdentifiers.recordingDevice != second.graphIdentifiers.recordingDevice)
    }

    @Test("An opted-in scope collapses one recorder to one device across samples")
    func scopeDeduplicatesTheRecorder() throws {
        let device = watch()
        let scoped = context(deviceIdentityScope: scope)
        let first = try converter.convert(sample(device, offset: 0), context: scoped)
        let second = try converter.convert(sample(device, offset: 600), context: scoped)
        #expect(first.graphIdentifiers.recordingDevice == second.graphIdentifiers.recordingDevice)
    }

    @Test("A firmware change mints a new device instead of mutating the shared one")
    func firmwareChangeMintsANewDevice() throws {
        let scoped = context(deviceIdentityScope: scope)
        let before = try converter.convert(sample(watch(firmware: "11.2"), offset: 0), context: scoped)
        let after = try converter.convert(sample(watch(firmware: "11.3"), offset: 600), context: scoped)
        #expect(before.graphIdentifiers.recordingDevice != after.graphIdentifiers.recordingDevice)
    }

    @Test("A device naming only its manufacturer falls back rather than collapsing every device")
    func degenerateFingerprintFailsClosed() throws {
        let vague = HKDevice(
            name: nil,
            manufacturer: "Apple Inc.",
            model: nil,
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        )
        let scoped = context(deviceIdentityScope: scope)
        let first = try converter.convert(sample(vague, offset: 0), context: scoped)
        let second = try converter.convert(sample(vague, offset: 600), context: scoped)
        #expect(first.graphIdentifiers.recordingDevice != second.graphIdentifiers.recordingDevice)
    }

    @Test("The digest matches the identity contract's published vector")
    func digestMatchesThePublishedVector() {
        #expect(
            GroveFHIRRecordingDeviceIdentity.value(
                scope: scope,
                adapter: "healthkit",
                recorder: .init(
                    manufacturer: "Apple Inc.",
                    model: "Watch",
                    hardwareVersion: "Watch7,12",
                    firmwareVersion: "11.2",
                    softwareVersion: "26.0"
                )
            ) == "v1:bb7862b04e576c946dd0a7dca35e139e5460552bff21c5f5da66c9bdc30fe064"
        )
        #expect(
            GroveFHIRRecordingDeviceIdentity.value(
                scope: scope,
                adapter: "healthkit",
                recorder: .init(
                    firmwareVersion: "11.2",
                    softwareVersion: "26.0",
                    localIdentifier: "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0"
                )
            ) == "v1:24315610739dc9f91e4b45d5ed48660d5a980827009c69d6899af2015c40caa0"
        )
    }
}

#endif
