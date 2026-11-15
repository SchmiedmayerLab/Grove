//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import CoreFoundation
import Foundation
import GroveFHIRContract
import HealthKit
import ModelsR4


/// Typed source-sample metadata, attached before record versioning.
/// Source keys and values remain metadata; they never establish clinical or writer identity.
@available(iOS 18, macOS 15, watchOS 11, *)
struct HealthKitSourceMetadata {
    static let url = HealthKitContract.metadataExtensionURL

    let container: Extension?
    let preservedKeys: Set<String>
    /// The keys the metadata policy excluded: counted, never reported as withheld.
    let excludedKeys: Set<String>
    let unsupportedCount: Int

    var summary: HealthKitFHIRExporter.Export.MetadataSummary {
        .init(preservedSampleKeys: preservedKeys.count, unsupportedSampleKeys: unsupportedCount, excludedSampleKeys: excludedKeys.count)
    }

    init(sample: HKSample, values: [String: Any], policy: HealthKitFHIRExporter.MetadataPolicy) {
        let excluded: Set<String> = switch policy {
        case .all: []
        case .nonIdentifying: Set(values.keys).intersection(HealthKitFHIRExporter.MetadataPolicy.identifyingKeys)
        case .omit: Set(values.keys)
        }
        var entries: [Extension] = []
        var preserved: Set<String> = []
        // Swift's default String ordering normalizes Unicode. The wire key is its exact UTF-8 spelling, so entries are
        // ordered by its bytes, as Grove's canonical JSON orders members.
        for key in values.keys.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) where !excluded.contains(key) {
            guard !key.isEmpty,
                  let value = values[key], let encodedValue = Self.value(value, key: key, sample: sample) else {
                continue
            }
            entries.append(Extension(
                extension: [
                    Extension(url: "key", value: .string(key.asFHIRStringPrimitive())),
                    Extension(url: "value", value: encodedValue)
                ],
                url: "entry"
            ))
            preserved.insert(key)
        }
        container = entries.isEmpty ? nil : Extension(
            extension: entries,
            url: FHIRPrimitive(FHIRURI(stringLiteral: Self.url))
        )
        preservedKeys = preserved
        excludedKeys = excluded
        unsupportedCount = values.count - preserved.count - excluded.count
    }

    /// Encode supported values with their FHIR types; unsupported values remain observable omissions.
    private static func value(_ value: Any, key: String, sample: HKSample) -> Extension.ValueX? {
        switch value {
        case let text as String:
            return text.isEmpty ? nil : .string(text.asFHIRStringPrimitive())
        case let number as NSNumber:
            // Swift and Objective-C Booleans bridge to CFBoolean. Integer 0/1 are still numbers.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .boolean(FHIRPrimitive(FHIRBool(number.boolValue)))
            }
            if let coding = metadataCoding(number, key: key) {
                return .coding(coding)
            }
            // A binary floating-point value travels as its shortest round-trip decimal, as every other Grove decimal
            // does; `decimalValue` would print 72.4 as 72.40000000000001. An integer or an `NSDecimalNumber` stays exact,
            // as a 64-bit integer has no exact binary64.
            if CFNumberIsFloatType(number as CFNumber), !(number is NSDecimalNumber) {
                return (try? GroveFHIRDecimal(number.doubleValue)).map { Extension.ValueX.decimal($0.primitive) }
            }
            let decimal = number.decimalValue
            return decimal.isNaN ? nil : .decimal(FHIRPrimitive(FHIRDecimal(decimal)))
        case let date as Date:
            guard date.timeIntervalSince1970.isFinite, let dateTime = try? HealthKitEffectiveTime.exactDateTime(date, offset: 0, zone: .utc) else {
                return nil
            }
            return .dateTime(FHIRPrimitive(dateTime))
        case let quantity as HKQuantity:
            return metadataQuantity(quantity, key: key, sample: sample).map(Extension.ValueX.quantity)
        default:
            return nil
        }
    }
}

#endif
