//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import HealthKit


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


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitCatalog {
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

    private static let unitsBySpelling: [String: HKUnit] = unitBindings.reduce(into: [:]) { units, binding in
        units[binding.ucumCode] = binding.unit
        units[binding.displayUnit] = binding.unit
    }

    private static let unitsByUCUMCode: [String: HKUnit] = unitBindings.reduce(into: [:]) { units, binding in
        units[binding.ucumCode] = units[binding.ucumCode] ?? binding.unit
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
}
