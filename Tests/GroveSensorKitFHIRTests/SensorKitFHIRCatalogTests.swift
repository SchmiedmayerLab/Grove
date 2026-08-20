//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import GroveSensorKitFHIR
import Testing


@Suite
struct SensorKitFHIRCatalogTests {
    @Test
    func inventoryIsCompleteSortedAndTruthful() {
        let catalog = SensorKitFHIRCatalog.current
        let tokens = catalog.entries.map(\.sourceToken)

        #expect(catalog.schemaVersion == 1)
        #expect(catalog.version == "0.2.0")
        #expect(catalog.fhirVersion == "4.0.1")
        #expect(tokens == tokens.sorted())
        #expect(Set(tokens).count == 24)
        #expect(catalog.entries.count { $0.scope == .groveImplemented } == 20)
        #expect(catalog.entries.count { $0.scope == .currentStableAddition } == 2)
        #expect(catalog.entries.count { $0.scope == .betaAddition } == 2)
    }

    @Test
    func implementedGroveSourcesArePinnedExactly() {
        let catalog = SensorKitFHIRCatalog.current
        let actual = Dictionary(uniqueKeysWithValues: catalog.entries.compactMap { entry in
            entry.groveSensor.map { (entry.sourceToken, $0) }
        })
        let expected = [
            "SRSensor.accelerometer": "Sensor.accelerometer",
            "SRSensor.ambientLightSensor": "Sensor.ambientLight",
            "SRSensor.ambientPressure": "Sensor.ambientPressure",
            "SRSensor.deviceUsageReport": "Sensor.deviceUsage",
            "SRSensor.electrocardiogram": "Sensor.ecg",
            "SRSensor.faceMetrics": "Sensor.faceMetrics",
            "SRSensor.heartRate": "Sensor.heartRate",
            "SRSensor.keyboardMetrics": "Sensor.keyboardMetrics",
            "SRSensor.mediaEvents": "Sensor.mediaEvents",
            "SRSensor.messagesUsageReport": "Sensor.messagesUsage",
            "SRSensor.odometer": "Sensor.odometer",
            "SRSensor.onWristState": "Sensor.onWrist",
            "SRSensor.pedometerData": "Sensor.pedometer",
            "SRSensor.phoneUsageReport": "Sensor.phoneUsage",
            "SRSensor.photoplethysmogram": "Sensor.ppg",
            "SRSensor.rotationRate": "Sensor.rotationRate",
            "SRSensor.siriSpeechMetrics": "Sensor.siriSpeechMetrics",
            "SRSensor.telephonySpeechMetrics": "Sensor.telephonySpeechMetrics",
            "SRSensor.visits": "Sensor.visits",
            "SRSensor.wristTemperature": "Sensor.wristTemperature"
        ]

        #expect(actual == expected)
    }

    @Test
    func onlyLosslessStructuredShapesClaimSupport() {
        let catalog = SensorKitFHIRCatalog.current
        let supported: [String: SensorKitFHIRStructuredContract] = Dictionary(
            uniqueKeysWithValues: catalog.entries.compactMap { entry in
                guard entry.status == .supported else {
                    return nil
                }
                return entry.structuredContract.map { (entry.sourceToken, $0) }
            }
        )

        #expect(supported == [
            "SRSensor.electrocardiogram": .electrocardiogram,
            "SRSensor.rotationRate": .sampledData
        ])
        #expect(catalog.entries.filter { $0.scope != .groveImplemented }.allSatisfy {
            $0.status == .deferred && $0.rawProfiles.isEmpty
        })
        #expect(catalog.entries.filter { $0.scope == .groveImplemented }.allSatisfy {
            !$0.rawProfiles.isEmpty
        })
        #expect(catalog.entries.filter { $0.status == .providerSpecific }.map(\.sourceToken) == [
            "SRSensor.deviceUsageReport",
            "SRSensor.onWristState",
            "SRSensor.visits"
        ])
    }
}
