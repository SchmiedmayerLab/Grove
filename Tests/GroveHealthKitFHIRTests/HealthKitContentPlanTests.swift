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


/// The compiled content plans' permanent invariants (oracle O6): the compiler reports no defect, every type has one
/// plan, the rule table is total, every document row converts to its document on every platform that has it, exactly
/// the known types state a metadata component, and every unit the plans read measures what it reads.
@Suite
struct HealthKitContentPlanTests {
    /// The profiles a recording or clinical-record document claims.
    private static let documentProfiles = [Profile.healthkitRecordingDocument, Profile.healthkitClinicalRecordDocument]

    @Test("The compiler reconciles every rule and every coded value with its contract")
    func compileDefectsAreEmpty() {
        #expect(HealthKitContentPlan.compileDefects.isEmpty, "\(HealthKitContentPlan.compileDefects)")
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

    @Test("Every rule names a distinct type; supported rows convert unless declared not yet; other admitted rows are not yet convertible")
    func ruleTableIsTotal() throws {
        let listed = HealthKitContentRules.groups.flatMap(\.types)
        #expect(listed.count == Set(listed).count, "a type is listed under two rules")
        let rows = Dictionary(uniqueKeysWithValues: HealthKitContract.rows.map { ($0.sourceTypeIdentifier, $0) })
        var unconverted: Set<HealthKitSourceType> = []
        for plan in HealthKitContentPlan.all {
            let type = plan.sourceType
            let row = try #require(rows[type.rawValue])
            guard Self.documentProfiles.allSatisfy({ !row.profiles.contains($0) }) else {
                Self.expectDocument(plan)
                continue
            }
            guard case .refused(let refusal) = plan.route else {
                #expect(!plan.outputs.isEmpty, "\(type.rawValue) converts but mints no outputs")
                #expect(row.implementationStatus == .supported, "\(type.rawValue) is \(row.implementationStatus) but converts")
                #expect(!plan.outputs.contains { $0.resourceType == .documentReference }, "\(type.rawValue)")
                continue
            }
            #expect(plan.outputs.isEmpty, "\(type.rawValue) is refused but mints outputs")
            switch row.implementationStatus {
            case .supported:
                unconverted.insert(type)
                #expect(refusal == .notYetConvertible(type))
            case .platformExclusive:
                // Admitted as a structured resource, not as a recording document, which no path emits yet.
                #expect(refusal == .notYetConvertible(type))
            case .intentionallyUnsupported:
                let expected: HealthKitConversionError = [.bloodPressureSystolic, .bloodPressureDiastolic].contains(type)
                    ? .componentRequiresCorrelation(type)
                    : .intentionallyUnsupported(type, reason: row.requirement ?? "")
                #expect(refusal == expected)
            }
        }
        #expect(unconverted == HealthKitContentRules.notYetConvertible)
    }

    @Test("Exactly heart rate, insulin delivery and menstrual flow state a metadata component, each read its own way")
    func metadataComponentsAreTheKnownSet() {
        var readings: [HealthKitSourceType: String] = [:]
        for plan in HealthKitContentPlan.all {
            if case .observation(let observation) = plan.route, let rule = observation.metadataComponent {
                readings[plan.sourceType] = "\(rule.field.key) \(rule.reading)"
            }
        }
        #expect(readings == [
            .heartRate: "\(HKMetadataKeyHeartRateMotionContext) optionalInteger",
            .insulinDelivery: "\(HKMetadataKeyInsulinDeliveryReason) requiredInteger",
            .menstrualFlow: "\(HKMetadataKeyMenstrualCycleStart) requiredBoolean"
        ])
    }

    @Test("Every unit a plan reads measures the quantity it reads, and every UCUM code the rules bind is read")
    func quantityUnitsAreCompatible() throws {
        var read = Self.electrocardiogramUnits()
        for plan in HealthKitContentPlan.all {
            guard case .observation(let observation) = plan.route else {
                continue
            }
            let type = HKQuantityTypeIdentifier(rawValue: plan.sourceType.rawValue)
            switch observation.value {
            case let .quantity(template, .unit(binding)):
                let quantityType = try #require(HKObjectType.quantityType(forIdentifier: type))
                #expect(quantityType.is(compatibleWith: binding.unit), "\(type.rawValue) cannot be read in \(binding.unit.unitString)")
                #expect(HealthKitContentRules.ucumUnits[binding.ucumCode] == binding.unit, "\(type.rawValue)")
                #expect(template.empty.code?.value?.string == binding.ucumCode, "\(type.rawValue)")
                read.insert(binding.ucumCode)
            case .quantity(_, .platformRate):
                let quantityType = try #require(HKObjectType.quantityType(forIdentifier: type))
                #expect(quantityType.is(compatibleWith: .count()), "\(type.rawValue) cannot be read as a count")
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
    /// Checks the plan of a row claiming a document profile: it mints its one document and converts to it, except a
    /// clinical record on watchOS, which has none: refused as platform exclusive, yet keeping its slot for retraction.
    private static func expectDocument(_ plan: HealthKitContentPlan) {
        let type = plan.sourceType.rawValue
        #expect(plan.outputs.map(\.resourceType) == [.documentReference], "\(type) mints \(plan.outputs)")
        let role = plan.outputs.first?.role
        switch plan.route {
        case .recording:
            #expect(role == HealthKitContentRules.nativeRecordingRole, "\(type)")
        case .clinical:
            #expect(role == HealthKitContentRules.clinicalRecordRole, "\(type)")
            #if os(watchOS)
            Issue.record("watchOS has no clinical records, yet \(type) converts to one")
            #endif
        case .refused(let refusal):
            #if os(watchOS)
            #expect(refusal == .platformExclusiveSourceType(plan.sourceType), "\(type)")
            #expect(role == HealthKitContentRules.clinicalRecordRole, "\(type)")
            #else
            Issue.record("\(type) claims a document profile, yet is refused with \(refusal)")
            #endif
        default:
            Issue.record("\(type) claims a document profile, yet converts through \(plan.route)")
        }
    }

    /// The UCUM codes the ECG reads its voltages and average heart rate in, each checked against the unit it is read in.
    private static func electrocardiogramUnits() -> Set<String> {
        guard case .electrocardiogram(let content) = HealthKitContentPlan[.electrocardiogram].route else {
            Issue.record("ECGs convert through no ECG content")
            return []
        }
        let claim = HealthKitElectrocardiogramClaim.self
        #expect(content.voltageUnit == HealthKitContentRules.ucumUnits[claim.voltageQuantity.code])
        #expect(content.averageHeartRateUnit == claim.averageHeartRateMeasurement.quantity.flatMap { HealthKitContentRules.ucumUnits[$0.code] })
        return Set([claim.voltageQuantity.code, claim.averageHeartRateMeasurement.quantity?.code].compactMap(\.self))
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
