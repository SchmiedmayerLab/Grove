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
import Testing


/// The compiled content plans' permanent invariants (oracle O6): the compile defects are the known set, every type
/// has one plan, the rule table is total, and every unit the plans read measures what it reads.
@Suite
struct HealthKitContentPlanTests {
    /// The walking-steadiness notification values, whose codes the contract does not admit: today's mapping states
    /// the guide's value and occurrence as one code.
    private static let knownDefects = [
        "HKCategoryTypeIdentifierAppleWalkingSteadinessEvent: value 1 reports as initial-low, which the contract does not admit",
        "HKCategoryTypeIdentifierAppleWalkingSteadinessEvent: value 2 reports as initial-very-low, which the contract does not admit",
        "HKCategoryTypeIdentifierAppleWalkingSteadinessEvent: value 3 reports as repeat-low, which the contract does not admit",
        "HKCategoryTypeIdentifierAppleWalkingSteadinessEvent: value 4 reports as repeat-very-low, which the contract does not admit"
    ]

    @Test("The compiler reconciles every rule with its contract except the known walking-steadiness values")
    func compileDefectsAreTheKnownSet() {
        #expect(HealthKitContentPlan.compileDefects == Self.knownDefects)
    }

    @Test("Every generated source type has exactly one plan, in inventory row order, found by type and by sample type")
    func everyTypeHasOnePlan() throws {
        let plans = HealthKitContentPlan.all
        #expect(plans.map(\.sourceType.rawValue) == HealthKitContract.rows.map(\.sourceTypeIdentifier))
        #expect(Set(plans.map(\.sourceType)) == Set(HealthKitSourceType.allCases))
        for plan in plans {
            #expect(HealthKitContentPlan[plan.sourceType] === plan)
            #expect(plan.entry.sourceTypeIdentifier == plan.sourceType.rawValue)
        }
        let heartRate = HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 60),
            start: Date(timeIntervalSince1970: 1_787_148_600),
            end: Date(timeIntervalSince1970: 1_787_148_600)
        )
        #expect(HealthKitContentPlan.plan(for: heartRate) === HealthKitContentPlan[.heartRate])
    }

    @Test("Every rule names a distinct type; supported rows convert unless declared not yet; documents mint documents")
    func ruleTableIsTotal() throws {
        let listed = HealthKitContentRules.groups.flatMap(\.types)
        #expect(listed.count == Set(listed).count, "a type is listed under two rules")
        var unconverted: Set<HealthKitSourceType> = []
        for plan in HealthKitContentPlan.all {
            let type = plan.sourceType
            let status = plan.entry.implementationStatus
            guard case .refused(let refusal) = plan.route else {
                #expect(!plan.outputs.isEmpty, "\(type.rawValue) converts but mints no outputs")
                #expect(status != .intentionallyUnsupported, "\(type.rawValue) is intentionally unsupported but converts")
                if status == .platformExclusive {
                    #expect(plan.outputs.map(\.output.resourceType) == [.documentReference], "\(type.rawValue) mints \(plan.outputs)")
                }
                continue
            }
            #expect(plan.outputs.isEmpty || Self.keepsOutputsWhenRefused(plan), "\(type.rawValue) is refused but mints outputs")
            switch status {
            case .supported:
                unconverted.insert(type)
                #expect(refusal == .unsupportedSourceType(type))
            case .platformExclusive:
                #expect(refusal == .platformExclusiveSourceType(type))
            case .intentionallyUnsupported:
                let expected: HealthKitConversionError = [.bloodPressureSystolic, .bloodPressureDiastolic].contains(type)
                    ? .componentRequiresCorrelation(type)
                    : .intentionallyUnsupported(type, reason: plan.entry.requirement ?? "")
                #expect(refusal == expected)
            }
        }
        #expect(unconverted == HealthKitContentRules.notYetConvertible)
    }

    @Test("Every unit a plan reads measures the quantity it reads, and every UCUM code the rules bind is read")
    func quantityUnitsAreCompatible() throws {
        var read: Set<String> = []
        for plan in HealthKitContentPlan.all {
            guard case .observation(let observation) = plan.route else {
                continue
            }
            let type = HKQuantityTypeIdentifier(rawValue: plan.sourceType.rawValue)
            switch observation.value {
            case let .quantity(template, .unit(unit)):
                let quantityType = try #require(HKObjectType.quantityType(forIdentifier: type))
                #expect(quantityType.is(compatibleWith: unit), "\(type.rawValue) cannot be read in \(unit.unitString)")
                if let binding = plan.unitBinding {
                    #expect(HealthKitContentRules.ucumUnits[binding.ucumCode] == unit, "\(type.rawValue)")
                    #expect(template.empty.code?.value?.string == binding.ucumCode, "\(type.rawValue)")
                    read.insert(binding.ucumCode)
                }
            case .quantity(let template, .percent):
                #expect(template.empty.code?.value?.string == "%", "\(type.rawValue) is read as a fraction but not stated in percent")
            case .bloodPressure(let members):
                for member in members {
                    let quantityType = try #require(HKObjectType.quantityType(forIdentifier: member.quantityType))
                    #expect(quantityType.is(compatibleWith: member.binding.unit), "\(member.quantityType.rawValue)")
                    #expect(member.template.quantity.empty.code?.value?.string == member.binding.ucumCode)
                    read.insert(member.binding.ucumCode)
                }
            case .workout(let workout):
                read.formUnion(try Self.workoutUnits(workout))
            default:
                break
            }
        }
        #expect(read == Set(HealthKitContentRules.ucumUnits.keys))
    }
}


extension HealthKitContentPlanTests {
    /// Whether a refused plan is a clinical type on watchOS, which keeps its output so a retraction can name it.
    private static func keepsOutputsWhenRefused(_ plan: HealthKitContentPlan) -> Bool {
        #if os(watchOS)
        plan.outputs.map(\.output.role) == [HealthKitContentRules.clinicalRecordRole]
        #else
        false
        #endif
    }

    /// The UCUM codes a workout's statistics are read in, each checked against every quantity type it reads.
    private static func workoutUnits(_ workout: HealthKitWorkoutContent) throws -> Set<String> {
        let activities = Array(workout.activities.values) + [workout.otherActivity]
        var read: Set<String> = []
        for statistic in workout.statistics {
            for identifier in Set(activities.map(statistic.quantityType(of:))) {
                let quantityType = try #require(HKObjectType.quantityType(forIdentifier: identifier))
                #expect(quantityType.is(compatibleWith: statistic.unit), "\(identifier.rawValue) in \(statistic.unit.unitString)")
            }
            read.formUnion([statistic.template.quantity.empty.code?.value?.string].compactMap(\.self))
        }
        return read
    }
}

#endif
