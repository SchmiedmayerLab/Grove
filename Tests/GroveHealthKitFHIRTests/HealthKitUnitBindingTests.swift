//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
@testable import GroveFHIRContract
import GroveHealthKit
@testable import GroveHealthKitFHIR
import HealthKit
import Testing


/// A sample HealthKit holds in a unit other than its contract's, and the `valueQuantity` the graph states for it.
struct UnitConversionCase: CustomTestStringConvertible, Sendable {
    let type: HKQuantityTypeIdentifier
    let unit: HKUnit
    let value: Double
    /// The decimal lexeme on the wire, exactly.
    let lexeme: String
    let code: String

    var testDescription: String { "\(value) \(unit.unitString) \(type.rawValue)" }
}


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

    /// The converter reads a value in its contract's unit whatever unit HealthKit holds it in. The wire lexeme is
    /// pinned exactly, binary noise included, so any change to the arithmetic is a visible, deliberate delta.
    @Test(arguments: [
        UnitConversionCase(type: .bodyTemperature, unit: .degreeFahrenheit(), value: 98.6, lexeme: "37.00000000000006", code: "Cel"),
        UnitConversionCase(type: .distanceWalkingRunning, unit: .mile(), value: 1, lexeme: "1609.344", code: "m"),
        UnitConversionCase(type: .oxygenSaturation, unit: .percent(), value: 0.07, lexeme: "7.000000000000001", code: "%"),
        UnitConversionCase(
            type: .bloodGlucose,
            unit: HKUnit.moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose).unitDivided(by: .liter()),
            value: 5.5,
            lexeme: "99.08573400002975",
            code: "mg/dL"
        )
    ])
    func convertsFromAnotherUnit(_ conversion: UnitConversionCase) throws {
        let sample = try GoldenFixtures.quantity(conversion.type, HKQuantity(unit: conversion.unit, doubleValue: conversion.value), uuid: GoldenFixtures.uuid(0xC8))
        var inputs = ExportInputs()
        inputs.sequence = 900
        let graph = try ExporterFixtures.export(sample, inputs).graph
        let quantity = try LosslessJSONValue(parsing: graph.json)["entry"]?.elements?.first?["resource"]?["valueQuantity"]
        #expect(quantity?["value"] == .number(conversion.lexeme))
        #expect(quantity?["code"]?.text == conversion.code)
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
