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


/// Structural equivalence of the compiled content plans with the content code they replace (oracle O3), for every
/// source type: the catalog the plans state, the route and value each type converts through, every unit, every
/// Observation's fixed parts and every coded value, compared with what today's tables and builders state.
///
/// Temporary: it reads the old content internals, so the old code's deletion (M6) deletes it; the goldens and the
/// content corpus then pin the plans' output.
@Suite
struct ContentPlanEquivalenceTests {
    /// The value kind each of today's bindings compiles to, by binding case.
    private static let valueKinds: [String: String] = [
        "quantity": "quantity", "percent": "quantity", "sessionRate": "quantity", "assessmentScore": "quantity",
        "severity": "coded", "presence": "coded", "categoryValue": "coded", "fixedCode": "coded", "notification": "coded",
        "sleepStage": "coded", "sessionDuration": "duration", "sexualActivity": "protection", "bloodPressure": "bloodPressure",
        "workout": "workout", "stateOfMind": "stateOfMind"
    ]

    @Test("Every plan states the public catalog's entry and outputs")
    func entriesAndOutputsAreTodays() {
        for plan in HealthKitContentPlan.all {
            let today = HealthKitCatalog[plan.sourceType]
            #expect(plan.entry.title == today.title)
            #expect(plan.entry.implementationStatus == today.implementationStatus)
            #expect(plan.entry.requirement == today.requirement)
            #expect(plan.entry.measurements.map(\.id) == today.measurements.map(\.id), "\(plan.sourceType.rawValue)")
            #expect(plan.entry.measurements.map(\.profiles) == today.measurements.map(\.profiles), "\(plan.sourceType.rawValue)")
            #expect(plan.outputs.map(\.output) == HealthKitCatalog.outputs(for: plan.sourceType), "\(plan.sourceType.rawValue)")
        }
    }

    @Test("Every type converts through today's route, and every refused type is refused with today's error")
    func routesAreTodays() {
        let documents: Set<HealthKitSourceType> = [.heartbeatSeries, .workoutRoute]
        let clinical = Set(HealthKitSourceType.allCases.filter { HealthKitCatalog.outputs(for: $0).map(\.role) == ["clinical-record"] })
        for plan in HealthKitContentPlan.all {
            let type = plan.sourceType
            let binding = HealthKitCatalog.binding(forSourceTypeIdentifier: type.rawValue)
            switch plan.route {
            case .observation(let observation):
                guard let binding else {
                    Issue.record("\(type.rawValue) has no binding today")
                    continue
                }
                let mismatch = Self.mismatch(observation, plan: plan, binding: binding)
                #expect(mismatch == nil, "\(type.rawValue): \(mismatch ?? "")")
            case .electrocardiogram:
                #expect(type == .electrocardiogram && binding == nil)
            case .recording(let document):
                #expect(documents.contains(type) && binding == nil, "\(type.rawValue)")
                #expect(plan.outputs.map(\.artifactFormatCode) == [document.format.rawValue])
            case .clinical(let document):
                #expect(clinical.contains(type) && binding == nil, "\(type.rawValue)")
                #expect(plan.outputs.map(\.artifactFormatCode) == [document.format.rawValue])
                #if os(watchOS)
                let today = HealthKitConverter.unconvertibleSampleError(for: type)
                Issue.record("\(type.rawValue) converts on watchOS, where today refuses it with \(today)")
                #endif
            case .refused(let refusal):
                #expect(binding == nil, "\(type.rawValue) has a binding today")
                #expect(refusal == HealthKitConverter.unconvertibleSampleError(for: type), "\(type.rawValue)")
            }
        }
    }

    @Test("Every output slot states the links, derivation and artifact today's drafts state")
    func slotsAreTodays() {
        for plan in HealthKitContentPlan.all {
            for slot in plan.outputs {
                let draft = slot.draft(.observation(Observation(code: CodeableConcept(), status: FHIRPrimitive(.final))))
                #expect(draft.role == slot.output.role && draft.discriminator == slot.output.discriminator)
                #expect(!draft.wasUserEntered && draft.writerRecord == nil && draft.clearIdentifiers.isEmpty)
                switch slot.output.resourceType {
                case .documentReference:
                    #expect(slot.links == [.subject, .recordingDevice, .studies] && !slot.derivedFromPrimary)
                    #expect(slot.artifactFormatCode != nil)
                default:
                    #expect(slot.links == .all && slot.artifactFormatCode == nil)
                    #expect(slot.derivedFromPrimary == (slot.output.retractionRole == .childOutput), "\(plan.sourceType.rawValue)")
                }
            }
        }
    }

    @Test("The plans' unit bindings, in row order with the blood-pressure members', are today's, and so is the reverse map")
    func unitBindingsAreTodays() {
        let members = Self.observationPlan(.bloodPressure).flatMap { plan -> [HealthKitUnitBinding] in
            guard case .bloodPressure(let members) = plan.value else {
                return []
            }
            return members.map(\.binding)
        }
        var seen: Set<String> = []
        let derived = (HealthKitContentPlan.all.compactMap(\.unitBinding) + (members ?? [])).filter { binding in
            seen.insert("\(binding.ucumCode)\u{0}\(binding.displayUnit)").inserted
        }
        #expect(derived.map(Self.strings) == HealthKitCatalog.unitBindings.map(Self.strings))
        var candidates: [String: [HKQuantityTypeIdentifier]] = [:]
        for plan in HealthKitContentPlan.all where plan.unitBinding != nil && plan.sourceType.rawValue.hasPrefix("HKQuantityTypeIdentifier") {
            candidates[plan.outputs[0].output.role, default: []].append(HKQuantityTypeIdentifier(rawValue: plan.sourceType.rawValue))
        }
        for contract in MeasurementCatalog.all + HealthKitMeasurementCatalog.all + [HealthKitContract.bodyMassIndex] {
            let today = try? HealthKitSampleProjection.quantityTypeIdentifier(for: contract.id)
            let planned = candidates[contract.id].flatMap { $0.count == 1 ? $0[0] : nil }
            #expect(planned == today, "\(contract.id)")
        }
    }
}


extension ContentPlanEquivalenceTests {
    /// The Observation plan of a source type, if it converts through one.
    static func observationPlan(_ type: HealthKitSourceType) -> ObservationPlan? {
        guard case .observation(let observation) = HealthKitContentPlan[type].route else {
            return nil
        }
        return observation
    }

    /// How an Observation plan differs from today's binding of its type, or `nil` when it does not.
    private static func mismatch(_ observation: ObservationPlan, plan: HealthKitContentPlan, binding: HealthKitFHIRBinding) -> String? {
        let contract = binding.contract
        let caseName = Mirror(reflecting: binding).children.first?.label ?? String(describing: binding)
        let effective: EffectiveRule = switch contract.effective {
        case .dateTime, .dateTimeOrPeriod: .instant
        case .period: .interval(nonZero: !HealthKitConverter.admitsEffectivePeriod(start: .distantPast, end: .distantPast, contract: contract))
        }
        let checks: [(String, Bool)] = [
            ("role", plan.outputs.map(\.output.role) == [contract.id]),
            ("profiles", observation.skeleton.meta?.profile == contract.profiles),
            ("effective", observation.effective == effective),
            ("value kind", valueKinds[caseName] == kind(of: observation.value)),
            ("quantity read", quantityReadMatches(observation.value, plan: plan, binding: binding))
        ]
        let failed = checks.filter { !$0.1 }.map(\.0)
        return failed.isEmpty ? nil : failed.joined(separator: ", ")
    }

    /// Whether a quantity plan reads the sample as today's binding does: in the same unit, bound the same way.
    private static func quantityReadMatches(_ value: ValueRule, plan: HealthKitContentPlan, binding: HealthKitFHIRBinding) -> Bool {
        guard case let .quantity(template, read) = value else {
            return true
        }
        let quantity = binding.contract.quantity
        guard template.empty.code?.value?.string == quantity?.code, template.domain == quantity?.valueDomain else {
            return false
        }
        switch (binding, read) {
        case let (.quantity(_, unit), .unit(planUnit)):
            return planUnit == unit && plan.unitBinding.map(strings) == [quantity?.code ?? "", quantity?.unit ?? "", unit.unitString]
        case (.sessionRate, .unit(let planUnit)):
            return planUnit == .count() && plan.unitBinding == nil
        case (.percent, .percent), (.assessmentScore, .score):
            return plan.unitBinding == nil
        default:
            return false
        }
    }

    /// The kind of a compiled value rule.
    private static func kind(of value: ValueRule) -> String {
        Mirror(reflecting: value).children.first?.label ?? String(describing: value)
    }

    /// A unit binding's UCUM code, display unit and HealthKit unit string.
    private static func strings(_ binding: HealthKitUnitBinding) -> [String] {
        [binding.ucumCode, binding.displayUnit, binding.unit.unitString]
    }
}

#endif
