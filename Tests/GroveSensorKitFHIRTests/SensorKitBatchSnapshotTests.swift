//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
@testable import GroveSensorKitFHIR
import Testing


struct SensorKitBatchSnapshotTests {
    @Test
    func retainsEveryDeviceFactAndFractionalInstant() throws {
        var device = RecordingDevice()
        device.stableUnitToken = "stable-unit"
        device.tokenScope = "participant"
        device.name = "Recording device"
        device.manufacturer = "Manufacturer"
        device.model = "Model"
        device.productType = "Watch1,1"
        device.systemName = "watchOS"
        device.systemVersion = "27.2"
        device.hardwareVersion = "hardware"
        device.firmwareVersion = "firmware"
        device.softwareVersion = "software"
        device.localIdentifier = "local"
        device.udiDeviceIdentifier = "udi-device"
        device.udiProductionIdentifier = "udi-production"
        device.serialNumber = "serial"
        let original = try snapshot(device: device)
        let bytes = try original.encoded(maximumByteCount: 16_384)
        let restored = try SensorKitBatchSnapshot(encoded: bytes, maximumByteCount: 16_384)
        #expect(restored == original)
        #expect(restored.recordingDevice == device)
        #expect(restored.sourceDevices == [device])
        #expect(try restored.encoded(maximumByteCount: 16_384) == bytes)
    }

    @Test
    func boundsBeforeDecodingAndAfterEncoding() throws {
        let original = try snapshot()
        let bytes = try original.encoded(maximumByteCount: 16_384)
        #expect(throws: SensorKitBatchSnapshot.SnapshotError.capacityExceeded) {
            try SensorKitBatchSnapshot(encoded: bytes, maximumByteCount: bytes.count - 1)
        }
        #expect(throws: SensorKitBatchSnapshot.SnapshotError.capacityExceeded) {
            try original.encoded(maximumByteCount: bytes.count - 1)
        }
        #expect(throws: SensorKitBatchSnapshot.SnapshotError.capacityExceeded) {
            try SensorKitBatchSnapshot(encoded: Data(), maximumByteCount: 16_384)
        }
    }

    @Test(arguments: ["version", "timeZone", "application"])
    func rejectsUnknownVersionOrInvalidRetainedFacts(field: String) throws {
        let bytes = try snapshot().encoded(maximumByteCount: 16_384)
        var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        switch field {
        case "version": object[field] = 2
        case "timeZone": object[field] = "Invalid/TimeZone"
        default:
            var application = try #require(object[field] as? [String: Any])
            application["bundleIdentifier"] = ""
            object[field] = application
        }
        let corrupted = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: (any Error).self) {
            try SensorKitBatchSnapshot(encoded: corrupted, maximumByteCount: 16_384)
        }
    }

    private func snapshot(device: RecordingDevice = RecordingDevice()) throws -> SensorKitBatchSnapshot {
        try SensorKitBatchSnapshot(
            application: SensorKitExporterFixtures.application,
            host: SensorFHIRIdentityTestSupport.converterHost,
            recordingDevice: device,
            sourceDevices: [device],
            sourceDevicesSuppliedEverySample: true,
            sourceTimeZone: SensorKitExporterFixtures.timeZone,
            conversionInstant: SensorKitExporterFixtures.instant.addingTimeInterval(0.123456)
        )
    }
}
