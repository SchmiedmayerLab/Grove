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
import ModelsR4
import Testing


/// Quantity and component templates: a contract's quantity built once, each sample stating only its value as the
/// shortest round-trip decimal inside the contract's domain.
@Suite
struct HealthKitQuantityTemplateTests {
    /// Every quantity contract in both generated catalogs, measurement and component alike.
    private static let quantities: [QuantityContract] = (MeasurementCatalog.all + HealthKitMeasurementCatalog.all).flatMap { contract in
        [contract.quantity].compactMap(\.self) + contract.components.compactMap(\.quantity)
    }

    /// Every quantity component in both generated catalogs.
    private static let components: [ComponentContract] = (MeasurementCatalog.all + HealthKitMeasurementCatalog.all)
        .flatMap(\.components)
        .filter { $0.quantity != nil }

    @Test("A quantity template states its contract's code, system, unit and domain, and no value")
    func templatesStateTheirContract() {
        #expect(!Self.quantities.isEmpty)
        for contract in Self.quantities {
            let template = QuantityTemplate(contract)
            #expect(template.empty.code?.value?.string == contract.code)
            #expect(template.empty.system?.value?.url.absoluteString == contract.system)
            #expect(template.empty.unit?.value?.string == contract.unit)
            #expect(template.empty.value == nil)
            #expect(template.domain == contract.valueDomain, "\(contract.code)")
        }
    }

    @Test("A quantity states the value's shortest round-trip decimal")
    func quantitiesStateTheShortestDecimal() throws {
        let template = QuantityTemplate(try #require(MeasurementCatalog.bodyTemperature.quantity))
        let lexemes: [(Double, String)] = [(36.52, "36.52"), (0.1 + 0.2, "0.30000000000000004"), (98, "98"), (-1, "-1"), (1.5, "1.5")]
        for (value, lexeme) in lexemes {
            let quantity = try template.quantity(value)
            #expect(quantity.value?.value?.decimal.description == lexeme)
            #expect(quantity.code == template.empty.code && quantity.system == template.empty.system && quantity.unit == template.empty.unit)
        }
    }

    @Test("A non-finite value is outside every domain, also where the contract states none")
    func nonFiniteValuesAreOutsideTheDomain() throws {
        let steps = QuantityTemplate(try #require(MeasurementCatalog.stepCount.quantity))
        let heartRate = QuantityTemplate(try #require(MeasurementCatalog.heartRate.quantity))
        #expect(heartRate.domain == nil)
        for template in [steps, heartRate] {
            for value in [Double.nan, .infinity, -.infinity] {
                #expect(throws: HealthKitConversionError.ValueFailure.outsideDomain) {
                    try template.quantity(value)
                }
            }
        }
    }

    /// Foundation's `Decimal` holds no finite binary64 beyond about 1e165 or below about 1e-128 in magnitude. Such a
    /// value is outside the domain when the domain excludes it; otherwise no registered rule names the refusal, and it
    /// is reported unclassified.
    @Test("A finite value without a Decimal is outside the domain only where the domain excludes it")
    func valuesWithoutADecimal() throws {
        let steps = QuantityTemplate(try #require(MeasurementCatalog.stepCount.quantity))
        let percentage = QuantityTemplate(try #require(MeasurementCatalog.oxygenSaturation.quantity))
        let heartRate = QuantityTemplate(try #require(MeasurementCatalog.heartRate.quantity))
        // Fractional for an integer-only contract, above 100, below zero.
        for (template, value) in [(steps, 5e-324), (percentage, 1e300), (steps, -1e300)] {
            #expect(throws: HealthKitConversionError.ValueFailure.outsideDomain, "\(value)") {
                try template.quantity(value)
            }
        }
        // An integer of at least zero, a fraction within 0 through 100, and any value of a contract without a domain.
        for (template, value) in [(steps, 1e200), (percentage, 5e-324), (heartRate, 5e-324), (heartRate, -1e300)] {
            #expect(throws: GroveFHIRDecimalError.self, "\(value)") {
                try template.quantity(value)
            }
        }
        let refusal = HealthKitConversionError(conversionFailure: GroveFHIRDecimalError.outsideFHIRDecimalDomain("5e-324"), source: .heartRate)
        #expect(refusal.diagnostic == ExchangeGraphRule.mobileInputUnclassified.diagnostic(at: "Bundle"))
        let outside = HealthKitConversionError.invalidValue(.stepCount, .outsideDomain)
        #expect(outside.diagnostic == ExchangeGraphRule.mobileInputValueOutsideDomain.diagnostic(at: "HKSample.value"))
    }

    /// The domain check of a value without a `Decimal` compares in binary64, which is exact only while every bound is.
    @Test("Every generated quantity domain's bounds are exact in binary64")
    func domainBoundsAreExactInBinary64() throws {
        let domains = Self.quantities.compactMap(\.valueDomain)
        #expect(!domains.isEmpty)
        for bound in domains.flatMap({ [$0.minimum] + [$0.maximum].compactMap(\.self) }) {
            let binary64 = try #require(Double(bound.value.description))
            #expect(Decimal(string: String(binary64), locale: .posix) == bound.value, "\(bound.value)")
        }
    }

    @Test("A component template states its code and its quantity of the value for every quantity component")
    func componentsStateTheirQuantity() throws {
        #expect(!Self.components.isEmpty)
        for contract in Self.components {
            // Every generated domain admits zero.
            let template = try #require(ComponentTemplate(contract))
            let component = try template.component(0)
            #expect(component.code == template.code)
            #expect(component.value == .quantity(try template.quantity.quantity(0)), "\(contract.id)")
        }
    }

    /// The coding a component states, written out, for every component with a quantity.
    @Test("A component template's code is the contract's code and system, without a display")
    func componentCodes() throws {
        for component in (MeasurementCatalog.all + HealthKitMeasurementCatalog.all).flatMap(\.components) {
            guard let template = ComponentTemplate(component) else {
                #expect(component.quantity == nil)
                continue
            }
            let coding = Coding(
                code: component.code.asFHIRStringPrimitive(),
                system: FHIRPrimitive(FHIRURI(stringLiteral: component.system))
            )
            #expect(template.code == CodeableConcept(coding: [coding]))
        }
    }

    @Test("The template refuses a value outside the contract's domain")
    func domainRefusal() throws {
        let template = QuantityTemplate(try #require(MeasurementCatalog.oxygenSaturation.quantity))
        #expect(throws: HealthKitConversionError.ValueFailure.outsideDomain) {
            try template.quantity(101)
        }
        #expect(try template.quantity(98).value?.value?.decimal == 98)
    }
}

#endif
