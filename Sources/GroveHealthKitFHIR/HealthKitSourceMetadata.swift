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


/// The typed metadata carrier used before record exchange, applied before record versioning.
/// Source keys and values remain metadata; they never establish clinical or writer identity.
@available(iOS 18, macOS 15, watchOS 11, *)
struct HealthKitSourceMetadata {
    static let url = HealthKitContract.metadataExtensionURL

    let container: Extension?
    let preservedKeys: Set<String>
    let unsupportedCount: Int
    let excludedCount: Int

    var summary: HealthKitFHIRExporter.Export.MetadataSummary {
        .init(preservedSampleKeys: preservedKeys.count, unsupportedSampleKeys: unsupportedCount, excludedSampleKeys: excludedCount)
    }

    init(sample: HKSample, values: [String: Any], disclosure: HealthKitFHIRExporter.Disclosure) {
        guard disclosure == .authorized else {
            container = nil
            preservedKeys = []
            unsupportedCount = 0
            excludedCount = values.count
            return
        }
        var entries: [Extension] = []
        var preserved: Set<String> = []
        // Swift's default String ordering normalizes Unicode. The wire key is its exact UTF-8 spelling.
        for key in values.keys.sorted(by: { $0.utf16.lexicographicallyPrecedes($1.utf16) }) {
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
        unsupportedCount = values.count - preserved.count
        excludedCount = 0
    }

    /// Adapted from the original metadata extension builder. No descriptive-string fallback can erase a type.
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
