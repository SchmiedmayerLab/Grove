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
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


/// The metadata bridge and the metadata components against what today's conversion reads from the same samples
/// (oracle O3). Temporary, like the rest of O3: the old code's deletion (M6) ports it to the bridge alone.
@Suite
struct HealthKitSampleMetadataTests {
    /// Metadata that exercises every reading the bridge makes: none, each key valid and wrongly typed, foreign keys.
    private static let metadata: [[String: any Sendable]] = [
        [:],
        [HKMetadataKeyTimeZone: "America/Los_Angeles"],
        [HKMetadataKeyTimeZone: "Not/AZone"],
        [HKMetadataKeyTimeZone: 5],
        [HKMetadataKeyWasUserEntered: true],
        [HKMetadataKeyWasUserEntered: false],
        [HKMetadataKeyWasUserEntered: 1],
        [HKMetadataKeyWasUserEntered: "true"],
        ["Foreign": 1, "Another": "value", HKMetadataKeyTimeZone: "UTC", HKMetadataKeyHeartRateMotionContext: 1],
        [HKMetadataKeySyncIdentifier: "record", HKMetadataKeySyncVersion: 3, HKMetadataKeyMenstrualCycleStart: true]
    ]

    @Test("Every plan consumes the adapter's typed allowlist")
    func everyPlanConsumesTheAllowlist() {
        #expect(HealthKitContentPlan.all.allSatisfy { $0.metadata.consumedKeys == HealthKitMetadataField.keys })
    }

    @Test("The bridge reads the time zone, manual entry and withheld keys as today's conversion does")
    func bridgeIsTodays() throws {
        let rule = HealthKitContentPlan[.heartRate].metadata
        for metadata in Self.metadata {
            let sample = try Self.heartRate(metadata: metadata)
            let bridged = HealthKitSampleMetadata(sample, rule: rule)
            let planned = Result { () throws(HealthKitValueFailure) in try bridged.timeZone() }
            let today = Result { () throws(HealthKitValueFailure) in try Self.todaysTimeZone(sample) }
            #expect(planned == today, "\(String(describing: metadata))")
            #expect(bridged.statesTimeZone == (sample.metadata?[HKMetadataKeyTimeZone] != nil))
            #expect(bridged.values.isEmpty == metadata.isEmpty)
            let facts = try HealthKitAssembly.SourceFacts(sample, options: .default)
            #expect(bridged.wasUserEntered == facts.wasUserEntered, "\(String(describing: metadata))")
            let withheld = facts.warnings.flatMap { warning in
                guard case .unmodeledMetadataWithheld(let keys) = warning else {
                    return [String]()
                }
                return keys
            }
            #expect(withheld == bridged.withheldKeys, "\(String(describing: metadata))")
        }
    }

    @Test("Each metadata component reads its key as today's builder does, absent, admitted, unadmitted and mistyped")
    func componentsAreTodays() throws {
        let values: [(HealthKitSourceType, [(any Sendable)?])] = [
            (.heartRate, [nil, 0, 1, 2, 3, -1, 1.5, "sedentary", true]),
            (.insulinDelivery, [nil, 0, 1, 2, 3, "bolus", true]),
            (.menstrualFlow, [nil, true, false, 0, 1, "true"])
        ]
        for (type, stated) in values {
            let plan = HealthKitContentPlan[type]
            guard case .observation(let observation) = plan.route, let rule = observation.metadataComponent,
                  let binding = HealthKitCatalog.binding(forSourceTypeIdentifier: type.rawValue) else {
                Issue.record("\(type.rawValue) states no metadata component")
                continue
            }
            for value in stated {
                let metadata: [String: any Sendable] = value.map { [rule.field.key: $0] } ?? [:]
                let sample = try Self.sample(plan, metadata: metadata)
                let planned = Result { () throws(HealthKitValueFailure) in
                    try rule.component(HealthKitSampleMetadata(sample, rule: plan.metadata))
                }
                let today = Result { () throws(HealthKitValueFailure) in try Self.todaysComponent(sample, binding: binding) }
                #expect(planned == today, "\(type.rawValue) \(String(describing: value))")
            }
        }
    }
}


extension HealthKitSampleMetadataTests {
    /// A heart-rate sample stating `metadata`.
    private static func heartRate(metadata: [String: any Sendable]) throws -> HKSample {
        try StoredSampleFixtures.quantitySample(
            HKQuantityType(.heartRate),
            value: 60,
            unit: .count().unitDivided(by: .minute()),
            facts: ContentPlanSamples.facts(metadata: metadata)
        )
    }

    /// A sample of an Observation plan's type that converts, stating `metadata` alone.
    private static func sample(_ plan: HealthKitContentPlan, metadata: [String: any Sendable]) throws -> HKSample {
        let facts = ContentPlanSamples.facts(metadata: metadata)
        switch plan.sourceType {
        case .menstrualFlow:
            let type = try ContentCorpusSamples.categoryType(plan.sourceType.rawValue)
            return try StoredSampleFixtures.categorySample(type, value: HKCategoryValueVaginalBleeding.light.rawValue, facts: facts)
        case .insulinDelivery:
            return try StoredSampleFixtures.quantitySample(HKQuantityType(.insulinDelivery), value: 1, unit: .internationalUnit(), facts: facts)
        default:
            return try heartRate(metadata: metadata)
        }
    }

    /// The time zone today's conversion reads from a sample.
    private static func todaysTimeZone(_ sample: HKSample) throws(HealthKitValueFailure) -> TimeZone? {
        do {
            return try HealthKitConverter.sourceTimeZone(metadata: sample.metadata ?? [:])
        } catch let failure as HealthKitValueFailure {
            throw failure
        } catch {
            Issue.record("Today's conversion refused with \(error)")
            throw .shapeInvalid
        }
    }

    /// The metadata component today's builder states last, or the value failure it refuses the sample with.
    private static func todaysComponent(_ sample: HKSample, binding: HealthKitFHIRBinding) throws(HealthKitValueFailure) -> ObservationComponent? {
        do {
            return try HealthKitConverter.observation(for: sample, binding: binding).component?.last
        } catch let failure as HealthKitValueFailure {
            throw failure
        } catch {
            Issue.record("Today's conversion refused with \(error)")
            throw .shapeInvalid
        }
    }
}

#endif
