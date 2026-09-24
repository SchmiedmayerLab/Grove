//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import GroveHealthKit
@testable import GroveHealthKitFHIR
import HealthKit
import Testing


/// The published UCUM-to-HealthKit correspondence.
///
/// HealthKit cannot parse UCUM, so a consumer holding a contract's unit has no way to derive the
/// HealthKit one. These hold the published mapping to what the bindings actually state.
@Suite
struct HealthKitUnitBindingTests {
    @Test
    func resolvesUnitsHealthKitCannotParseItself() {
        #expect(HealthKitCatalog.unit(forUCUMCode: "Cel") == .degreeCelsius())
        #expect(HealthKitCatalog.unit(forUCUMCode: "{steps}") == .count())
        #expect(HealthKitCatalog.unit(forUCUMCode: "/min") == HKUnit.count() / .minute())
        #expect(HealthKitCatalog.unit(forUCUMCode: "kcal") == .kilocalorie())
        #expect(HealthKitCatalog.unit(forUCUMCode: "mm[Hg]") == .millimeterOfMercury())
    }

    /// Several measurements share one UCUM code while naming it differently for display, and a
    /// consumer reading `Observation.value.unit` meets the display rather than the code.
    @Test
    func resolvesEveryDisplaySpellingOfASharedCode() {
        let perMinute = HKUnit.count() / .minute()
        #expect(HealthKitCatalog.unit(forUnitSpelling: "beats/minute") == perMinute)
        #expect(HealthKitCatalog.unit(forUnitSpelling: "breaths/minute") == perMinute)
        #expect(HealthKitCatalog.unit(forUnitSpelling: "revolutions/minute") == perMinute)
        #expect(HealthKitCatalog.unit(forUnitSpelling: "/min") == perMinute)
        #expect(HealthKitCatalog.unit(forUnitSpelling: "steps") == .count())
        #expect(HealthKitCatalog.unit(forUnitSpelling: "Cel") == .degreeCelsius())
    }

    @Test
    func reportsNothingForAUnitTheAdapterDoesNotBind() {
        #expect(HealthKitCatalog.unit(forUCUMCode: "parsecs") == nil)
        // UCUM spells a year `a`, which HealthKit has no unit for; only provider measurements use it.
        #expect(HealthKitCatalog.unit(forUCUMCode: "a") == nil)
    }

    /// Every binding must state a unit HealthKit accepts, which is the whole point of publishing
    /// them: a binding whose HealthKit unit came from the UCUM string would have raised instead.
    @Test
    func everyBindingStatesBothSpellings() {
        #expect(!HealthKitCatalog.unitBindings.isEmpty)
        for binding in HealthKitCatalog.unitBindings {
            #expect(!binding.ucumCode.isEmpty)
            #expect(!binding.displayUnit.isEmpty)
            #expect(HealthKitCatalog.unit(forUnitSpelling: binding.ucumCode) == binding.unit)
            #expect(HealthKitCatalog.unit(forUnitSpelling: binding.displayUnit) == binding.unit)
        }
    }

    /// One spelling never names two different HealthKit units. The reverse does not hold — every
    /// annotation unit is `count` — which is why no inverse lookup is published.
    @Test
    func eachSpellingNamesOneUnit() {
        var units: [String: HKUnit] = [:]
        for binding in HealthKitCatalog.unitBindings {
            for spelling in [binding.ucumCode, binding.displayUnit] {
                if let existing = units[spelling] {
                    #expect(existing == binding.unit, "\(spelling) names two units")
                }
                units[spelling] = binding.unit
            }
        }
    }
}

#endif
