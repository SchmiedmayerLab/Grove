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
import HealthKit
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    /// The metadata keys this converter reads into modelled elements.
    ///
    /// A key here is already carried somewhere in the output, so retaining it again would state the
    /// same fact twice and let the two copies disagree. Everything else is unmodelled by definition.
    static let modelledMetadataKeys: Set<String> = [
        HKMetadataKeyAppleECGAlgorithmVersion,
        HKMetadataKeyHeartRateMotionContext,
        HKMetadataKeyInsulinDeliveryReason,
        HKMetadataKeyMenstrualCycleStart,
        HKMetadataKeySexualActivityProtectionUsed,
        HKMetadataKeySyncIdentifier,
        HKMetadataKeySyncVersion,
        HKMetadataKeyTimeZone,
        HKMetadataKeyWasUserEntered
    ]

    /// Metadata keys that identify a record across systems.
    ///
    /// Retaining one links this record to the same record in another system, which is exactly what
    /// makes it useful and exactly what makes it linkable. ``HealthKitLinkableMetadataPolicy``
    /// decides; omission is the default.
    static let linkableMetadataKeys: Set<String> = [
        HKMetadataKeyExternalUUID,
        HKMetadataKeyDeviceSerialNumber,
        HKMetadataKeyUDIDeviceIdentifier,
        HKMetadataKeyUDIProductionIdentifier
    ]

    /// Every metadata entry the contract does not otherwise model, carried verbatim.
    ///
    /// `HKSample.metadata` is an open dictionary: any writer may set any key, and Apple adds keys
    /// between SDK releases. Reading only the known keys discards the rest silently, which is the one
    /// way this converter could lose source data without failing. Retaining them keeps the conversion
    /// lossless without pretending the values have a modelled meaning.
    static func retainedMetadataComponents(
        of sample: HKSample,
        policy: HealthKitLinkableMetadataPolicy
    ) -> [ObservationComponent] {
        guard let metadata = sample.metadata else {
            return []
        }
        return metadata
            .filter { !modelledMetadataKeys.contains($0.key) }
            .filter { policy == .authorized || !linkableMetadataKeys.contains($0.key) }
            .sorted { $0.key < $1.key }
            .compactMap { key, value in
                retainedValue(value).map { retained in
                    ObservationComponent(
                        code: CodeableConcept(text: key.asFHIRStringPrimitive()),
                        value: retained
                    )
                }
            }
    }

    /// The retained shape of one metadata value.
    ///
    /// HealthKit stores numbers, strings, dates, and quantities. A value of any other type is not
    /// dropped quietly: it is rendered through its own description, so the entry survives as a
    /// string rather than disappearing.
    private static func retainedValue(_ value: Any) -> ObservationComponent.ValueX? {
        switch value {
        case let string as String:
            return .string(string.asFHIRStringPrimitive())
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            return .boolean(FHIRPrimitive(FHIRBool(number.boolValue)))
        case let date as Date:
            return (try? DateTime(date: date)).map { .dateTime(FHIRPrimitive($0)) }
        case let quantity as HKQuantity:
            return .string(quantity.description.asFHIRStringPrimitive())
        case let number as NSNumber:
            return .string(number.stringValue.asFHIRStringPrimitive())
        default:
            return .string(String(describing: value).asFHIRStringPrimitive())
        }
    }
}
#endif
