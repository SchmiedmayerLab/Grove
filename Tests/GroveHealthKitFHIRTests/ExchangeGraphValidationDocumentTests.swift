//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit) && !os(watchOS)

import Darwin
import Foundation
@testable import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


/// Pins what the shared validation JSON may stand in for, and that a graph releases its own temporaries.
@Suite
struct ExchangeGraphValidationDocumentTests {
    enum Scenario: String, CaseIterable, CustomTestStringConvertible {
        case heartRate
        case heartRateWithStudies
        case gatewayHeartRateWithDevice
        case bloodPressure

        var testDescription: String { rawValue }
    }

    private static let timestamp = Date(timeIntervalSince1970: 1_787_148_600)
    private static let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

    private static func conversions(_ scenario: Scenario) throws -> ExportedRecord {
        switch scenario {
        case .heartRate:
            return try ExporterFixtures.export(heartRateSample(), inputs())
        case .heartRateWithStudies:
            return try ExporterFixtures.export(heartRateSample(), inputs(studies: [.test("a"), .test("b")]))
        case .gatewayHeartRateWithDevice:
            return try ExporterFixtures.export(
                heartRateSample(device: HKDevice(
                    name: "Band",
                    manufacturer: "Example Device Company",
                    model: "Band One",
                    hardwareVersion: nil,
                    firmwareVersion: nil,
                    softwareVersion: nil,
                    localIdentifier: "band-1",
                    udiDeviceIdentifier: nil
                )),
                inputs(converterWasGateway: true)
            )
        case .bloodPressure:
            let dates = (start: timestamp, end: timestamp.addingTimeInterval(60))
            func pressure(_ type: HKQuantityTypeIdentifier, _ value: Double) -> HKQuantitySample {
                HKQuantitySample(
                    type: HKQuantityType(type),
                    quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: value),
                    start: dates.start,
                    end: dates.end
                )
            }
            return try ExporterFixtures.export(
                HKCorrelation(
                    type: HKCorrelationType(.bloodPressure),
                    start: dates.start,
                    end: dates.end,
                    objects: [pressure(.bloodPressureSystolic, 118), pressure(.bloodPressureDiastolic, 76)]
                ),
                inputs()
            )
        }
    }

    private static func inputs(
        studies: [StudyEnrollment] = [],
        converterWasGateway: Bool = false
    ) -> ExportInputs {
        var inputs = ExportInputs()
        inputs.graphIdentifierSystem = "https://study.example.org/fhir/identifiers/mobile-graph"
        inputs.instant = timestamp
        inputs.studies = studies
        inputs.options.role = converterWasGateway ? .gateway : .assembler
        inputs.options.recordingDevice = .custom(FixedTokenRecordingDeviceResolver(token: "band"))
        return inputs
    }

    private static func heartRateSample(device: HKDevice? = nil) -> HKQuantitySample {
        HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: beatsPerMinute, doubleValue: 72),
            start: timestamp,
            end: timestamp.addingTimeInterval(60),
            device: device,
            metadata: nil
        )
    }

    private static func expectSharedJSONMatchesStandaloneEncodes(_ graph: ExchangeGraph) throws {
        let entries = try #require(graph.bundle.entry)
        #expect(entries.count > 1)
        let documents = [
            ExchangeGraph.ValidationDocument(bundle: graph.bundle, jsonData: graph.json),
            ExchangeGraph.ValidationDocument(bundle: graph.bundle, jsonData: nil)
        ]
        for document in documents {
            for (index, entry) in entries.enumerated() {
                let resource = try #require(entry.resource)
                let standalone = try JSONSerialization.jsonObject(with: JSONEncoder().encode(resource))
                let shared = try #require(try document.resourceObject(at: index))
                #expect(try canonical(shared) == canonical(standalone), "Bundle.entry[\(index)]")
                #expect((shared as? NSDictionary) == (standalone as? NSDictionary), "Bundle.entry[\(index)]")
            }
            let bundle = try JSONSerialization.jsonObject(with: JSONEncoder().encode(graph.bundle))
            #expect(try canonical(document.bundleObject()) == canonical(bundle))
            #expect(try document.resourceObject(at: entries.count) == nil)
        }
    }

    private static func canonical(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func liveHeapBytes() -> Int {
        var statistics = malloc_statistics_t()
        malloc_zone_statistics(nil, &statistics)
        return Int(statistics.size_in_use)
    }

    @Test("An entry's resource in the parsed Bundle is the standalone encode of that resource", arguments: Scenario.allCases)
    func parsedEntryResourceIsTheStandaloneEncode(scenario: Scenario) throws {
        for graph in try Self.conversions(scenario).all.map(\.graph) {
            try Self.expectSharedJSONMatchesStandaloneEncodes(graph)
        }
    }

    /// A graph's Foundation temporaries (its parsed JSON trees) would otherwise stay in the caller's pool until a
    /// whole batch finishes: ~44 KB per graph here without the graph's own pool, ~2 KB with it. Live heap bytes are
    /// process-wide and other suites run concurrently, so the smallest growth over two rounds is held to a bound
    /// well between the two.
    @Test(
        "Building a graph leaves no Foundation temporaries in the caller's autorelease pool",
        .disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "Process-wide heap measurement is too noisy on shared CI runners")
    )
    func graphValidationDrainsItsOwnTemporaries() throws {
        let (exporter, _) = try ExporterFixtures.exporter(Self.inputs())
        let sample = Self.heartRateSample()
        let stored = try ExportedRecord(ExporterFixtures.collect(exporter, samples: [sample], at: Self.timestamp).exports).graph.json
        let iterations = 500
        let round = { () throws -> Int in
            try autoreleasepool {
                let before = Self.liveHeapBytes()
                for _ in 0..<iterations {
                    _ = try ExporterFixtures.collect(exporter, samples: [sample], at: Self.timestamp)
                    _ = try ExchangeGraph(validating: stored, kind: .active)
                }
                return Self.liveHeapBytes() - before
            }
        }
        _ = try round()
        let retained = try (0..<2).map { _ in try round() }.min() ?? .max
        #expect(retained < 8 << 20, "\(retained) bytes stayed in the caller's pool over \(iterations) conversions")
    }
}

#endif
