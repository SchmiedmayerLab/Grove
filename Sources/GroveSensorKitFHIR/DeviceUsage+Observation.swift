//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(SensorKit)

import FHIRModelsExtensions
import Foundation
public import GroveSensorKit
public import ModelsR4
import SensorKit


@available(iOS 18, *)
extension SRDeviceUsageReport.SafeRepresentation: SensorKitObservationConvertible {
    public static let profile: FHIRPrimitive<Canonical> =
        "https://grovealliance.org/fhir/core/StructureDefinition/grove-device-usage-observation"
    public static let category = GroveSensorKitVocabulary.category("activity", "Activity")

    public func hashIdentifierContent(into hasher: inout SensorKitSampleIDHasher) {
        hasher.combine(Sensor.deviceUsage.srSensor.rawValue)
        hasher.combine(timestamp)
        hasher.combine(duration)
        hasher.combine(totalScreenWakes)
        hasher.combine(totalUnlocks)
        hasher.combine(totalUnlockDuration)
        // The breakdowns travel in the batch this observation derives from, so two
        // reports that agree on every counter but not on their detail are two records.
        hashAppUsage(into: &hasher)
        hashNotificationUsage(into: &hasher)
        hashWebUsage(into: &hasher)
    }

    public func buildObservation(_ observation: inout Observation) throws {
        observation.code = CodeableConcept(coding: [
            sampleTypeCoding(Sensor.deviceUsage.srSensor.rawValue, "Device Usage")
        ])
        observation.effective = .period(Period(
            end: FHIRPrimitive(try DateTime(date: timestamp + duration)),
            start: FHIRPrimitive(try DateTime(date: timestamp))
        ))
        // The scalar summary lives in the Observation; the per-app, per-notification,
        // and per-web breakdowns are too heterogeneous for coded components and travel
        // as a raw batch the observation derives from.
        observation.value = .quantity(Quantity(
            code: "s".asFHIRStringPrimitive(),
            system: GroveSensorKitVocabulary.ucum,
            unit: "seconds".asFHIRStringPrimitive(),
            value: try totalUnlockDuration.asFHIRDecimalPrimitiveSafe()
        ))
        observation.component = [
            ObservationComponent(
                code: GroveSensorKitVocabulary.concept("screen-wakes", "Screen Wakes"),
                value: .quantity(Quantity(
                    code: "{count}".asFHIRStringPrimitive(),
                    system: GroveSensorKitVocabulary.ucum,
                    unit: "wakes".asFHIRStringPrimitive(),
                    value: FHIRPrimitive(FHIRDecimal(Decimal(totalScreenWakes)))
                ))
            ),
            ObservationComponent(
                code: GroveSensorKitVocabulary.concept("unlocks", "Unlocks"),
                value: .quantity(Quantity(
                    code: "{count}".asFHIRStringPrimitive(),
                    system: GroveSensorKitVocabulary.ucum,
                    unit: "unlocks".asFHIRStringPrimitive(),
                    value: FHIRPrimitive(FHIRDecimal(Decimal(totalUnlocks)))
                ))
            )
        ]
    }
}


@available(iOS 18, *)
extension SRDeviceUsageReport.SafeRepresentation {
    /// The breakdowns keyed in ascending category order — dictionary iteration order is
    /// not stable, and the digest has to survive a re-fetch.
    private func sorted<Usage>(_ breakdown: [CategoryKey: [Usage]]) -> [(key: CategoryKey, value: [Usage])] {
        breakdown.sorted { $0.key.rawValue < $1.key.rawValue }
    }

    private func hashAppUsage(into hasher: inout SensorKitSampleIDHasher) {
        for (category, usages) in sorted(appUsageByCategory) {
            hasher.combine(category.rawValue)
            for usage in usages {
                hasher.combine(usage.bundleIdentifier)
                hasher.combine(usage.reportApplicationIdentifier)
                hasher.combine(usage.relativeStartTime)
                hasher.combine(usage.usageTime)
                for session in usage.textInputSessions {
                    hasher.combine(session.identifier)
                    hasher.combine(session.sessionType.rawValue)
                    hasher.combine(session.duration)
                }
                for supplemental in usage.supplementalCategories {
                    hasher.combine(supplemental.identifier)
                }
            }
        }
    }

    private func hashNotificationUsage(into hasher: inout SensorKitSampleIDHasher) {
        for (category, usages) in sorted(notificationUsageByCategory) {
            hasher.combine(category.rawValue)
            for usage in usages {
                hasher.combine(usage.bundleIdentifier)
                hasher.combine(usage.event.rawValue)
            }
        }
    }

    private func hashWebUsage(into hasher: inout SensorKitSampleIDHasher) {
        for (category, usages) in sorted(webUsageByCategory) {
            hasher.combine(category.rawValue)
            for usage in usages {
                hasher.combine(usage.totalUsageTime)
            }
        }
    }
}

#endif
