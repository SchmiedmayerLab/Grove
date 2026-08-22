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
        #expect(catalog.version == "0.3.0")
        #expect(catalog.fhirVersion == "4.0.1")
        #expect(tokens == tokens.sorted())
        #expect(Set(tokens).count == 22)
        #expect(catalog.entries.count { $0.scope == .catalogBaseline } == 20)
        #expect(catalog.entries.count { $0.scope == .stableAddition } == 2)
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
        #expect(catalog.entries.filter { $0.scope != .catalogBaseline }.allSatisfy {
            $0.rawProfiles.isEmpty
        })
        #expect(catalog.entries.filter { $0.scope == .catalogBaseline }.allSatisfy {
            !$0.rawProfiles.isEmpty
        })
        #expect(catalog.entries.filter { $0.status == .platformExclusive }.map(\.sourceToken) == [
            "SRSensor.accelerometer",
            "SRSensor.deviceUsageReport",
            "SRSensor.keyboardMetrics",
            "SRSensor.messagesUsageReport",
            "SRSensor.onWristState",
            "SRSensor.phoneUsageReport",
            "SRSensor.photoplethysmogram",
            "SRSensor.sleepSessions",
            "SRSensor.visits"
        ])
    }

    @Test
    func everyAdmittedRawRowDeclaresItsRegistryFormats() throws {
        let catalog = SensorKitFHIRCatalog.current

        #expect(catalog.entries.allSatisfy { $0.rawProfiles.isEmpty == $0.rawFormats.isEmpty })
        let formats: [String: [String]] = Dictionary(
            uniqueKeysWithValues: catalog.entries.map { ($0.sourceTypeCode, $0.rawFormats) }
        )
        #expect(formats["accelerometer"] == ["grove-csv-1"])
        #expect(formats["ppg"] == ["grove-ppg-1"])
        #expect(formats["device-usage"] == ["fhir-json-1", "native-json-1"])
        #expect(formats["keyboard-metrics"] == ["native-json-1"])
        #expect(formats["sleep-sessions"]?.isEmpty == true)
    }
}
