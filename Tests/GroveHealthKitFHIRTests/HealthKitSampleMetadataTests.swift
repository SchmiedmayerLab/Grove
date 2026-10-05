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


/// The metadata bridge, which reads a sample's metadata once for its whole conversion, and the metadata components:
/// each key absent, valid, of an unadmitted value and of the wrong type, and foreign keys.
@Suite
struct HealthKitSampleMetadataTests {
    /// What the bridge reads from one sample's metadata.
    struct BridgeCase: Sendable {
        /// The sample's metadata.
        let metadata: [String: any Sendable]
        /// The zone it names, or why it names none HealthKit knows.
        let zone: Result<TimeZone?, HealthKitConversionError.ValueFailure>
        /// Whether it states manual entry.
        var wasUserEntered = false
        /// The keys it withholds.
        var withheldKeys: [String] = []
    }

    /// One metadata component's outcome.
    enum ComponentOutcome {
        /// No component.
        case none
        /// The component stating the coded value of `raw`.
        case value(Int)
        /// A refusal.
        case failure(HealthKitConversionError.ValueFailure)

        /// The outcome as `rule` states it.
        func result(of rule: MetadataComponentRule) -> Result<ObservationComponent?, HealthKitConversionError.ValueFailure> {
            switch self {
            case .none: .success(nil)
            case .value(let raw): .success(rule.values[raw].map { ObservationComponent(code: rule.code, value: .codeableConcept($0)) })
            case .failure(let failure): .failure(failure)
            }
        }
    }

    /// Metadata that exercises every reading the bridge makes: none, each key valid and wrongly typed, foreign keys.
    private static let bridgeCases: [BridgeCase] = [
        BridgeCase(metadata: [:], zone: .success(nil)),
        BridgeCase(metadata: [HKMetadataKeyTimeZone: "America/Los_Angeles"], zone: .success(TimeZone(identifier: "America/Los_Angeles"))),
        BridgeCase(metadata: [HKMetadataKeyTimeZone: "Not/AZone"], zone: .failure(.unsupportedMetadataValue(.timeZone))),
        BridgeCase(metadata: [HKMetadataKeyTimeZone: 5], zone: .failure(.unsupportedMetadataValue(.timeZone))),
        BridgeCase(metadata: [HKMetadataKeyWasUserEntered: true], zone: .success(nil), wasUserEntered: true),
        BridgeCase(metadata: [HKMetadataKeyWasUserEntered: false], zone: .success(nil)),
        BridgeCase(metadata: [HKMetadataKeyWasUserEntered: 1], zone: .success(nil)),
        BridgeCase(metadata: [HKMetadataKeyWasUserEntered: "true"], zone: .success(nil)),
        BridgeCase(
            metadata: ["Foreign": 1, "Another": "value", HKMetadataKeyTimeZone: "UTC", HKMetadataKeyHeartRateMotionContext: 1],
            zone: .success(TimeZone(identifier: "UTC")),
            withheldKeys: ["Another", "Foreign"]
        ),
        BridgeCase(metadata: [HKMetadataKeySyncIdentifier: "record", HKMetadataKeySyncVersion: 3, HKMetadataKeyMenstrualCycleStart: true], zone: .success(nil))
    ]

    @Test("Every plan consumes the adapter's typed allowlist")
    func everyPlanConsumesTheAllowlist() {
        #expect(HealthKitContentPlan.all.allSatisfy { $0.metadata.consumedKeys == HealthKitConversionError.MetadataField.keys })
    }

    @Test("The bridge reads the time zone, manual entry and withheld keys")
    func bridgeReadsTheMetadata() throws {
        let rule = HealthKitContentPlan[.heartRate].metadata
        for expected in Self.bridgeCases {
            let bridged = HealthKitSampleMetadata(try Self.heartRate(metadata: expected.metadata), rule: rule)
            let label = String(describing: expected.metadata)
            #expect(Result { () throws(HealthKitConversionError.ValueFailure) in try bridged.timeZone() } == expected.zone, "\(label)")
            #expect(bridged.statesTimeZone == (expected.metadata[HKMetadataKeyTimeZone] != nil), "\(label)")
            #expect(bridged.values.count == expected.metadata.count, "\(label)")
            #expect(bridged.wasUserEntered == expected.wasUserEntered, "\(label)")
            #expect(bridged.withheldKeys == expected.withheldKeys, "\(label)")
        }
    }

    @Test("Each metadata component reads its key absent, admitted, unadmitted and mistyped")
    func componentsReadTheirKey() throws {
        let cases: [(HealthKitSourceType, [((any Sendable)?, ComponentOutcome)])] = [
            (.heartRate, [
                (nil, .none), (0, .value(0)), (1, .value(1)), (2, .value(2)), (3, .failure(.unsupportedMetadataValue(.heartRateMotionContext))),
                (-1, .failure(.unsupportedMetadataValue(.heartRateMotionContext))), (1.5, .value(1)), ("sedentary", .none), (true, .value(1))
            ]),
            (.insulinDelivery, [
                (nil, .failure(.requiredMetadataMissing(.insulinDeliveryReason))), (0, .failure(.unsupportedMetadataValue(.insulinDeliveryReason))),
                (1, .value(1)), (2, .value(2)), (3, .failure(.unsupportedMetadataValue(.insulinDeliveryReason))),
                ("bolus", .failure(.requiredMetadataMissing(.insulinDeliveryReason))), (true, .value(1))
            ]),
            (.menstrualFlow, [
                (nil, .failure(.requiredMetadataMissing(.menstrualCycleStart))), (true, .value(1)), (false, .value(0)),
                (0, .failure(.unsupportedMetadataValue(.menstrualCycleStart))), (1, .failure(.unsupportedMetadataValue(.menstrualCycleStart))),
                ("true", .failure(.unsupportedMetadataValue(.menstrualCycleStart)))
            ])
        ]
        for (type, stated) in cases {
            let plan = HealthKitContentPlan[type]
            guard case .observation(let observation) = plan.route, let rule = observation.metadataComponent else {
                Issue.record("\(type.rawValue) states no metadata component")
                continue
            }
            for (value, expected) in stated {
                let metadata: [String: any Sendable] = value.map { [rule.field.key: $0] } ?? [:]
                let bridged = HealthKitSampleMetadata(try Self.sample(plan, metadata: metadata), rule: plan.metadata)
                let read = Result { () throws(HealthKitConversionError.ValueFailure) in try rule.component(bridged) }
                #expect(read == expected.result(of: rule), "\(type.rawValue) \(String(describing: value))")
            }
        }
    }
}


extension HealthKitSampleMetadataTests {
    /// The facts of a sample stating `metadata`.
    private static func facts(metadata: [String: any Sendable]) -> StoredSampleFixtures.SampleFacts {
        let start = Date(timeIntervalSince1970: 1_787_148_600)
        return StoredSampleFixtures.SampleFacts(
            uuid: GoldenFixtures.uuid(0xE0),
            start: start,
            end: start.addingTimeInterval(60),
            device: nil,
            metadata: metadata.isEmpty ? nil : metadata,
            writer: .unattributed
        )
    }

    /// A heart-rate sample stating `metadata`.
    private static func heartRate(metadata: [String: any Sendable]) throws -> HKSample {
        try StoredSampleFixtures.quantitySample(
            HKQuantityType(.heartRate),
            value: 60,
            unit: .count().unitDivided(by: .minute()),
            facts: facts(metadata: metadata)
        )
    }

    /// A sample of an Observation plan's type that converts, stating `metadata` alone.
    private static func sample(_ plan: HealthKitContentPlan, metadata: [String: any Sendable]) throws -> HKSample {
        switch plan.sourceType {
        case .menstrualFlow:
            let type = try ContentCorpusSamples.categoryType(plan.sourceType.rawValue)
            return try StoredSampleFixtures.categorySample(type, value: HKCategoryValueVaginalBleeding.light.rawValue, facts: facts(metadata: metadata))
        case .insulinDelivery:
            return try StoredSampleFixtures.quantitySample(HKQuantityType(.insulinDelivery), value: 1, unit: .internationalUnit(), facts: facts(metadata: metadata))
        default:
            return try heartRate(metadata: metadata)
        }
    }
}

#endif
