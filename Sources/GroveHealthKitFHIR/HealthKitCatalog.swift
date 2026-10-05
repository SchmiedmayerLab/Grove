//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

public import GroveFHIRContract
public import HealthKit
public import ModelsR4


/// One measurement and its exact direct profile claims in the HealthKit adapter matrix.
public struct HealthKitMeasurementContract: Sendable {
    public let id: String
    public let profiles: [FHIRPrimitive<Canonical>]
}


/// One output a source type's conversion mints, and how a retraction names it.
public struct HealthKitOutput: Hashable, Sendable {
    public let role: String
    public let discriminator: String
    public let resourceType: ResourceType
    public let retractionRole: RetractionTargetRole
}


/// One authoritative row in the HealthKit implementation matrix.
public struct HealthKitCatalogEntry: Sendable {
    public let sourceTypeIdentifier: String
    public let title: String
    /// The one selected contract, or all candidate contracts when source facts cannot select one.
    public let measurements: [HealthKitMeasurementContract]
    public let implementationStatus: HealthKitImplementationStatus
    public let requirement: String?
}


/// One measurement's unit, as UCUM states it and as HealthKit spells it.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct HealthKitUnitBinding: Sendable {
    /// The UCUM code the Grove measurement contract binds, such as `Cel`.
    public let ucumCode: String
    /// The display unit the contract states, such as `beats/minute`.
    public let displayUnit: String
    /// The HealthKit unit the adapter reads and writes the measurement in.
    public let unit: HKUnit
}


/// Closed, fail-closed catalog used by ``HealthKitFHIRExporter``.
///
/// This catalog alone determines whether the public API may claim a Grove profile.
@available(iOS 18, macOS 15, watchOS 11, *)
public enum HealthKitCatalog {
    /// Every platform identifier in the frozen HealthKit inventory, including characteristics
    /// and other non-sample identifiers that are outside the exporter's input type. The
    /// sleep-duration aggregate lives in the catalog's derivedAggregates, not in these rows.
    /// A consumer can render this directly as the implementation coverage matrix.
    public static let entries: [HealthKitCatalogEntry] = HealthKitContentPlan.all.map(\.entry)

    /// Every unit this adapter binds, as the pair of spellings the same quantity carries.
    ///
    /// UCUM and HealthKit disagree on how to spell a unit, and HealthKit cannot parse UCUM at all:
    /// `HKUnit(from: "Cel")` raises rather than returning degrees Celsius, and the same holds for
    /// the annotation units, the rate units, and `dB[SPL]`. A consumer that has a contract's UCUM
    /// code and needs the HealthKit unit therefore cannot derive one from the other, which is why
    /// the correspondence is published rather than left to be rediscovered.
    /// One binding per distinct pair of spellings: several measurements share a UCUM code while
    /// naming it differently for display — `/min` is `beats/minute`, `breaths/minute`, and
    /// `revolutions/minute` — and a consumer holding any of those spellings needs the same unit.
    ///
    /// The bindings are the content plans' own, in inventory row order: every quantity read in its contract's unit,
    /// then the blood-pressure panel's members, whose unit no scalar quantity binds although the adapter consumes and
    /// emits it.
    public static let unitBindings: [HealthKitUnitBinding] = {
        let members = HealthKitContentPlan.all.flatMap { plan -> [HealthKitUnitBinding] in
            guard case .observation(let observation) = plan.route, case .bloodPressure(let members) = observation.value else {
                return []
            }
            return members.map(\.binding)
        }
        var seen: Set<String> = []
        return (HealthKitContentPlan.all.compactMap(\.unitBinding) + members).filter { binding in
            seen.insert("\(binding.ucumCode)\u{0}\(binding.displayUnit)").inserted
        }
    }()

    /// Each binding's unit under its UCUM code and under its display unit; a later binding wins a shared spelling.
    private static let unitsBySpelling: [String: HKUnit] = unitBindings.reduce(into: [:]) { units, binding in
        units[binding.ucumCode] = binding.unit
        units[binding.displayUnit] = binding.unit
    }

    /// Each binding's unit under its UCUM code; the first binding wins a shared code.
    private static let unitsByUCUMCode: [String: HKUnit] = unitBindings.reduce(into: [:]) { units, binding in
        units[binding.ucumCode] = units[binding.ucumCode] ?? binding.unit
    }

    /// Every output the converter mints for one source type, in the order the graph emits them.
    ///
    /// A caller holding only a source type — a deletion, whose sample is already gone — names the outputs an
    /// addition minted. One exception: an ECG's average-heart-rate child is listed whether or not the ECG stated an
    /// average, so the retraction of an ECG without one also names a child that was never emitted. A deletion cannot
    /// tell the two apart, and the pinned guide has no source-record retraction scope yet (an IG gap; a draft
    /// exists); a receiver resolves the extra target to nothing.
    public static func outputs(for type: HealthKitSourceType) -> [HealthKitOutput] {
        HealthKitContentPlan[type].outputs.map(\.output)
    }

    /// The HealthKit unit a UCUM code names, or `nil` when this adapter binds no measurement to it.
    ///
    /// There is deliberately no inverse. A HealthKit unit does not determine a UCUM code: every
    /// annotation unit this adapter binds — steps, flights, strokes, and the rest — is `count` in
    /// HealthKit, so answering the other direction would have to pick one arbitrarily. A caller
    /// holding a measurement already has its code on the contract.
    public static func unit(forUCUMCode code: String) -> HKUnit? {
        unitsByUCUMCode[code]
    }

    /// The HealthKit unit a UCUM code or a contract's display unit names.
    public static func unit(forUnitSpelling spelling: String) -> HKUnit? {
        unitsBySpelling[spelling]
    }

    /// The inventory row of a source type; every generated type has one.
    public static subscript(type: HealthKitSourceType) -> HealthKitCatalogEntry {
        HealthKitContentPlan[type].entry
    }
}


extension HealthKitSourceType {
    /// The inventory row of a sample type, such as the one a deletion was reported for.
    public init?(_ sampleType: HKSampleType) {
        self.init(rawValue: sampleType.identifier)
    }
}

#endif
