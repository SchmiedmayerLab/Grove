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


/// What converting a sample's value comes to: the value, a value failure, or any other refusal.
enum ContentPlanOutcome: Equatable {
    /// The Observation's value.
    case value(Observation.ValueX?)
    /// The value failure the sample is refused with.
    case failure(HealthKitValueFailure)
    /// Any other refusal, described.
    case other(String)
}


/// Samples a plan and today's builders both convert: one minute long, in no time zone, stating what each type
/// requires.
enum ContentPlanSamples {
    /// When every sample starts.
    static let start = Date(timeIntervalSince1970: 1_787_148_600)

    /// The facts of a sample lasting `duration` seconds and stating `metadata`.
    static func facts(duration: TimeInterval = 60, metadata: [String: any Sendable] = [:]) -> StoredSampleFixtures.SampleFacts {
        StoredSampleFixtures.SampleFacts(
            uuid: GoldenFixtures.uuid(0xE0),
            start: start,
            end: start.addingTimeInterval(duration),
            device: nil,
            metadata: metadata.isEmpty ? nil : metadata,
            writer: .unattributed
        )
    }

    /// The metadata a type states to convert at all.
    static func requiredMetadata(_ type: HealthKitSourceType) -> [String: any Sendable] {
        switch type {
        case .insulinDelivery: [HKMetadataKeyInsulinDeliveryReason: HKInsulinDeliveryReason.basal.rawValue]
        case .menstrualFlow: [HKMetadataKeyMenstrualCycleStart: true]
        default: [:]
        }
    }

    /// A sample of an Observation plan's type stating `metadata` beside what the type requires; a category sample
    /// states `raw`. `nil` for another route.
    static func sample(
        _ plan: HealthKitContentPlan,
        raw: Int = HKCategoryValue.notApplicable.rawValue,
        metadata: [String: any Sendable] = [:]
    ) throws -> HKSample? {
        guard case .observation(let observation) = plan.route else {
            return nil
        }
        let facts = facts(metadata: requiredMetadata(plan.sourceType).merging(metadata) { _, stated in stated })
        let identifier = plan.sourceType.rawValue
        switch observation.value {
        case let .quantity(template, read):
            return try quantity(identifier, template: template, read: read, facts: facts)
        case .coded, .duration, .protection:
            return try StoredSampleFixtures.categorySample(try ContentCorpusSamples.categoryType(identifier), value: raw, facts: facts)
        case .bloodPressure:
            return try bloodPressure(systolic: 120, diastolic: 80, facts: facts)
        case .workout:
            return try StoredSampleFixtures.workout(activity: HKWorkoutActivityType.running.rawValue, duration: 60, statistics: [], facts: facts)
        case .stateOfMind:
            return try StoredSampleFixtures.stateOfMind(kind: 1, valence: 0.5, labels: [], associations: [], facts: facts)
        }
    }

    /// A blood-pressure correlation of the two readings, in mmHg.
    static func bloodPressure(systolic: Double, diastolic: Double, facts: StoredSampleFixtures.SampleFacts) throws -> HKCorrelation {
        let members = try [(HKQuantityTypeIdentifier.bloodPressureSystolic, systolic), (.bloodPressureDiastolic, diastolic)].map { type, value in
            var member = facts
            member.uuid = GoldenFixtures.uuid(type == .bloodPressureSystolic ? 0xE1 : 0xE2)
            return try StoredSampleFixtures.quantitySample(HKQuantityType(type), value: value, unit: .millimeterOfMercury(), facts: member)
        }
        return try StoredSampleFixtures.correlation(HKCorrelationType(.bloodPressure), objects: members, facts: facts)
    }

    /// A quantity sample its contract admits, or a scored assessment.
    private static func quantity(
        _ identifier: String,
        template: QuantityTemplate,
        read: QuantityRead,
        facts: StoredSampleFixtures.SampleFacts
    ) throws -> HKSample? {
        switch read {
        case .unit, .platformRate:
            let unit = if case .unit(let binding) = read { binding.unit } else { HKUnit.count() }
            let value = [1, 50, 100, 1_000, 0.5, 0].first { template.domain?.contains(Decimal($0)) != false } ?? 1
            return try StoredSampleFixtures.quantitySample(try ContentCorpusSamples.quantityType(identifier), value: value, unit: unit, facts: facts)
        case .percent:
            return try StoredSampleFixtures.quantitySample(try ContentCorpusSamples.quantityType(identifier), value: 0.25, unit: .percent(), facts: facts)
        case .score:
            return try StoredSampleFixtures.scoredAssessment(HKScoredAssessmentTypeIdentifier(rawValue: identifier), score: 1, facts: facts)
        }
    }
}


extension ContentPlanEquivalenceTests {
    /// Every metadata key an Observation component reads, each at a value its component admits: every type's sample
    /// states all of them, so a plan states a metadata component exactly where today's builder does.
    private static let componentMetadata: [String: any Sendable] = [
        HKMetadataKeyHeartRateMotionContext: HKHeartRateMotionContext.active.rawValue,
        HKMetadataKeyInsulinDeliveryReason: HKInsulinDeliveryReason.bolus.rawValue,
        HKMetadataKeyMenstrualCycleStart: false
    ]

    @Test("Every Observation plan's skeleton, quantity and metadata component are what today's builder states")
    func skeletonsAreTodays() throws {
        let componentCodes = HealthKitContentPlan.all.compactMap { plan -> CodeableConcept? in
            guard case .observation(let observation) = plan.route else {
                return nil
            }
            return observation.metadataComponent?.code
        }
        var unconverted: [HealthKitSourceType] = []
        for plan in HealthKitContentPlan.all {
            guard case .observation(let observation) = plan.route,
                  let binding = HealthKitCatalog.binding(forSourceTypeIdentifier: plan.sourceType.rawValue) else {
                continue
            }
            guard let conversion = try Self.firstConversion(plan, binding: binding) else {
                unconverted.append(plan.sourceType)
                continue
            }
            let (sample, today) = conversion
            let metadata = HealthKitSampleMetadata(sample, rule: plan.metadata)
            let planned = try observation.metadataComponent.flatMap { try $0.component(metadata) }
            let stated = today.component?.filter { componentCodes.contains($0.code) } ?? []
            #expect(stated == [planned].compactMap(\.self), "\(plan.sourceType.rawValue) states another metadata component")
            let skeleton = observation.skeleton
            let type = plan.sourceType.rawValue
            #expect(today.code == skeleton.code, "\(type)")
            #expect(today.status == skeleton.status && today.meta == skeleton.meta, "\(type)")
            #expect(today.extension == skeleton.extension, "\(type)")
            #expect(today.category == skeleton.category, "\(type)")
            #expect(today.method == skeleton.method, "\(type)")
            if case let .quantity(template, _) = observation.value, case .quantity(var quantity)? = today.value {
                quantity.value = nil
                #expect(quantity == template.empty, "\(type)")
            }
        }
        // Today's mapping refuses every walking-steadiness value; its plan's fixed parts are compiled like the rest.
        #expect(unconverted == [.appleWalkingSteadinessEvent])
    }

    @Test("Every coded plan maps each raw value from -5 through 200 as today's builders do")
    func codedValuesAreTodays() throws {
        var mismatches: [String] = []
        for plan in HealthKitContentPlan.all {
            guard case .observation(let observation) = plan.route, case let .coded(values, unresolved) = observation.value,
                  let binding = HealthKitCatalog.binding(forSourceTypeIdentifier: plan.sourceType.rawValue) else {
                continue
            }
            for raw in -5...200 {
                let sample = try #require(try ContentPlanSamples.sample(plan, raw: raw))
                let planned: ContentPlanOutcome = if let value = values[raw] {
                    .value(.codeableConcept(value))
                } else {
                    .failure(unresolved.contains(raw) ? .missingNormativeCode : .unsupportedValue(raw))
                }
                let today = Self.todaysValue(sample, binding: binding)
                if today != planned {
                    mismatches.append("\(plan.sourceType.rawValue) \(raw): \(today) != \(planned)")
                }
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches)")
    }

    @Test("Every duration is today's in the contract's unit, and sexual activity states today's protection codes")
    func durationsAndProtectionAreTodays() throws {
        for plan in HealthKitContentPlan.all {
            guard case .observation(let observation) = plan.route,
                  let binding = HealthKitCatalog.binding(forSourceTypeIdentifier: plan.sourceType.rawValue) else {
                continue
            }
            switch observation.value {
            case let .duration(template, secondsPerUnit):
                let category = try ContentCorpusSamples.categoryType(plan.sourceType.rawValue)
                let sample = try StoredSampleFixtures.categorySample(category, value: 0, facts: ContentPlanSamples.facts(duration: 90))
                let today = Self.todaysValue(sample, binding: binding)
                #expect(today == .value(.quantity(try template.quantity(90 / secondsPerUnit))), "\(plan.sourceType.rawValue)")
            case let .protection(unknown, protected, unprotected):
                let category = try ContentCorpusSamples.categoryType(plan.sourceType.rawValue)
                let key = HKMetadataKeySexualActivityProtectionUsed
                let protections: [([String: any Sendable], CodeableConcept)] = [([:], unknown), ([key: true], protected), ([key: false], unprotected)]
                for (metadata, value) in protections {
                    let sample = try StoredSampleFixtures.categorySample(category, value: 0, facts: ContentPlanSamples.facts(metadata: metadata))
                    #expect(Self.todaysValue(sample, binding: binding) == .value(.codeableConcept(value)), "\(metadata)")
                }
            default:
                continue
            }
        }
    }

    @Test("Blood pressure reads today's members, in today's order and unit, as today's components")
    func bloodPressureIsTodays() throws {
        guard case .bloodPressure(let members)? = Self.observationPlan(.bloodPressure)?.value else {
            Issue.record("Blood pressure converts through no panel")
            return
        }
        #expect(members.map(\.quantityType) == [.bloodPressureSystolic, .bloodPressureDiastolic])
        #expect(members.map(\.component) == ["systolic", "diastolic"])
        let sample = try ContentPlanSamples.bloodPressure(systolic: 15.9987, diastolic: 10.6658, facts: ContentPlanSamples.facts())
        let binding = try #require(HealthKitCatalog.binding(for: sample))
        let today = try HealthKitConverter.observation(for: sample, binding: binding)
        let readings = [HKQuantityTypeIdentifier.bloodPressureSystolic: 15.9987, .bloodPressureDiastolic: 10.6658]
        let planned = try members.map { member in
            let reading = HKQuantity(unit: .millimeterOfMercury(), doubleValue: readings[member.quantityType] ?? 0)
            return try member.template.component(reading.doubleValue(for: member.binding.unit))
        }
        #expect(today.component == planned)
        #expect(today.value == nil)
    }
}


extension ContentPlanEquivalenceTests {
    /// The plan's first sample that today converts, stating every component's metadata key, and today's Observation
    /// of it: a category type tries every raw value up to 200.
    private static func firstConversion(_ plan: HealthKitContentPlan, binding: HealthKitFHIRBinding) throws -> (HKSample, Observation)? {
        for raw in 0...200 {
            guard let sample = try ContentPlanSamples.sample(plan, raw: raw, metadata: componentMetadata) else {
                return nil
            }
            if let observation = try? HealthKitConverter.observation(for: sample, binding: binding) {
                return (sample, observation)
            }
        }
        return nil
    }

    /// Today's value of a sample, or how it is refused.
    private static func todaysValue(_ sample: HKSample, binding: HealthKitFHIRBinding) -> ContentPlanOutcome {
        do {
            return .value(try HealthKitConverter.observation(for: sample, binding: binding).value)
        } catch let failure as HealthKitValueFailure {
            return .failure(failure)
        } catch {
            return .other(String(describing: error))
        }
    }
}

#endif
