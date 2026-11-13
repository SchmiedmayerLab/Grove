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


@Suite
struct HealthKitSourceMetadataTests {
    private static func sample() -> HKQuantitySample {
        HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 72),
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 0)
        )
    }

    private static func sourceValue(_ item: [String: Any]) throws -> Any {
        let kind = try #require(item["sourceType"] as? String)
        switch kind {
        case "integer":
            return NSDecimalNumber(string: try #require(item["source"] as? String))
        case "date":
            let value = try #require(item["source"] as? String)
            return try #require(ISO8601DateFormatter().date(from: value))
        case "quantity":
            let source = try #require(item["source"] as? [String: Any])
            let unit = try #require(source["unit"] as? String)
            return HKQuantity(unit: HKUnit(from: unit), doubleValue: try #require(source["value"] as? Double))
        default:
            return try #require(item["source"])
        }
    }

    @Test("Shared legacy fixtures preserve typed values and quantity semantics")
    func legacyValues() throws {
        let url = try #require(Bundle.module.url(forResource: "healthkit-metadata-legacy-values", withExtension: "fixture"))
        let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try #require(fixture["cases"] as? [[String: Any]])
        for item in cases {
            let key = try #require(item["key"] as? String)
            let source = try Self.sourceValue(item)
            let encoded = HealthKitSourceMetadata(sample: Self.sample(), values: [key: source], disclosure: .authorized)
            #expect(encoded.preservedKeys == [key])
            #expect(encoded.unsupportedCount == 0)
            let container = try #require(encoded.container)
            let actual = try #require(container.extension?.first?.extension?.last)
            let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(actual)) as? [String: Any])
            let valueKey = try #require(item.keys.first { $0.hasPrefix("value") })
            if valueKey == "valueDateTime" {
                let date = try #require(object[valueKey] as? String)
                #expect(ISO8601DateFormatter().date(from: date) == source as? Date)
            } else if let expected = item[valueKey] as? [String: Any] {
                let actual = try #require(object[valueKey] as? [String: Any])
                for (name, value) in expected {
                    #expect((actual[name] as? NSObject)?.isEqual(value) == true)
                }
            } else {
                #expect((object[valueKey] as? NSObject)?.isEqual(item[valueKey]) == true)
            }
        }
    }

    @Test("Numeric zero and one are not Booleans, and unsupported values are counted without logging them")
    func typeDistinctionAndOmissions() throws {
        let metadata = HealthKitSourceMetadata(
            sample: Self.sample(),
            values: [
            "boolean": NSNumber(value: true), "zero": NSNumber(value: 0), "one": NSNumber(value: 1),
            "empty": "", "array": ["private"], "infinite": NSNumber(value: Double.infinity)
            ],
            disclosure: .authorized
        )
        #expect(metadata.preservedKeys == ["boolean", "zero", "one"])
        #expect(metadata.unsupportedCount == 3)
        let entries = try #require(metadata.container?.extension).compactMap { $0.extension?.last }
        guard case .boolean? = entries[0].value, case .decimal? = entries[1].value, case .decimal? = entries[2].value else {
            Issue.record("Metadata source types were changed")
            return
        }
    }

    @Test("Custom quantity keys use a compatible unit; reserved key characters do not change key identity")
    func customQuantitiesAndKeys() throws {
        let metadata = HealthKitSourceMetadata(
            sample: Self.sample(),
            values: [
            "a/b": HKQuantity(unit: .mile(), doubleValue: 1), "a%2Fb": "literal"
            ],
            disclosure: .authorized
        )
        let entries = try #require(metadata.container?.extension)
        let keys = entries.compactMap { entry -> String? in
            guard case .string(let key)? = entry.extension?.first?.value else {
                return nil
            }
            return key.value?.string
        }
        #expect(keys == ["a%2Fb", "a/b"])
        guard case .quantity(let quantity)? = entries[1].extension?.last?.value else {
            Issue.record("Custom quantity was not preserved")
            return
        }
        #expect(quantity.code?.value?.string == "m")
        #expect(quantity.value?.value?.decimal == Decimal(string: "1609.344"))
    }

    @Test("Preservation changes record version while source/output identities remain stable; exclusion is explicit")
    func recordIdentity() throws {
        let sample = try StoredSampleFixtures.quantitySample(
            HKQuantityType(.heartRate),
            value: 72,
            unit: .count().unitDivided(by: .minute()),
            facts: HealthKitMetadataWarningTests.facts(0xD8, metadata: ["com.example.note": "after exercise"])
        )
        let preserved = try AssemblyFixtures.conversion(sample)
        var inputs = ExportInputs()
        inputs.options.metadata = .omit
        let omitted = try AssemblyFixtures.conversion(sample, inputs)
        #expect(preserved.identifiers.sourceRecord == omitted.identifiers.sourceRecord)
        #expect(preserved.identifiers.primaryOutput == omitted.identifiers.primaryOutput)
        #expect(preserved.record.json != omitted.record.json)
        #expect(preserved.record.json == (try AssemblyFixtures.conversion(sample)).record.json)
        #expect(preserved.withheldMetadataKeys.isEmpty)
        #expect(preserved.export.metadata?.preservedSampleKeys == 1)
        #expect(omitted.export.metadata?.excludedSampleKeys == 1)
        #expect(omitted.export.metadata?.unsupportedSampleKeys == 0)
    }

    @Test("SDK codings preserve the step-test case and never truncate fractional values")
    func enumerationValues() throws {
        #expect(HealthKitSourceMetadata.metadataCoding(NSNumber(value: 2.5), key: HKMetadataKeyHeartRateMotionContext) == nil)
        if #available(iOS 26, macOS 26, watchOS 26, *) {
            let coding = try #require(HealthKitSourceMetadata.metadataCoding(
                NSNumber(value: HKVO2MaxTestType.predictionStepTest.rawValue), key: HKMetadataKeyVO2MaxTestType
            ))
            #expect(coding.code?.value?.string == String(HKVO2MaxTestType.predictionStepTest.rawValue))
            #expect(coding.display?.value?.string == "Prediction Step Test")
        }
    }

    @Test("Known quantity keys reject incompatible dimensions instead of choosing a fallback unit")
    func knownQuantityDimensions() {
        let metadata = HealthKitSourceMetadata(
            sample: Self.sample(),
            values: [
                HKMetadataKeyWeatherTemperature: HKQuantity(unit: .meter(), doubleValue: 1),
                HKMetadataKeySessionEstimate: HKQuantity(unit: .meter(), doubleValue: 1)
            ],
            disclosure: .authorized
        )
        #expect(metadata.container == nil)
        #expect(metadata.unsupportedCount == 2)
    }

    @Test(
        "Metadata percentages use the same decimal scaling as clinical quantities",
        arguments: [HKMetadataKeyWeatherHumidity, HKMetadataKeyAlpineSlopeGrade],
        [(0.282, "28.2"), (0.29, "29"), (0.975, "97.5")]
    )
    func percentQuantities(key: String, value: (fraction: Double, expected: String)) throws {
        let metadata = HealthKitSourceMetadata(
            sample: Self.sample(),
            values: [key: HKQuantity(unit: .percent(), doubleValue: value.fraction)],
            disclosure: .authorized
        )
        let encoded = try #require(metadata.container?.extension?.first?.extension?.last?.value)
        guard case .quantity(let quantity) = encoded else {
            Issue.record("Metadata percentage must be a quantity")
            return
        }
        #expect(quantity.code?.value?.string == "%")
        #expect(quantity.value?.value?.decimal.description == value.expected)
        #expect(metadata.preservedKeys == [key])
        #expect(metadata.unsupportedCount == 0)
    }
}

#endif
