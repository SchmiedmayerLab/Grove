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
            $0.status == .deferred && $0.rawProfiles.isEmpty
        })
        #expect(catalog.entries.filter { $0.scope == .catalogBaseline }.allSatisfy {
            !$0.rawProfiles.isEmpty
        })
        #expect(catalog.entries.filter { $0.status == .platformExclusive }.map(\.sourceToken) == [
            "SRSensor.deviceUsageReport",
            "SRSensor.onWristState",
            "SRSensor.visits"
        ])
    }
}
