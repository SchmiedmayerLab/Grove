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

    @Test("A quantity states the value's shortest round-trip decimal and refuses a non-finite value")
    func quantitiesStateTheShortestDecimal() throws {
        let template = QuantityTemplate(try #require(MeasurementCatalog.bodyTemperature.quantity))
        let lexemes: [(Double, String)] = [(36.52, "36.52"), (0.1 + 0.2, "0.30000000000000004"), (98, "98"), (-1, "-1"), (1.5, "1.5")]
        for (value, lexeme) in lexemes {
            let quantity = try template.quantity(value)
            #expect(quantity.value?.value?.decimal.description == lexeme)
            #expect(quantity.code == template.empty.code && quantity.system == template.empty.system && quantity.unit == template.empty.unit)
        }
        for value in [Double.nan, .infinity, -.infinity] {
            #expect(throws: HealthKitConversionError.ValueFailure.shapeInvalid) {
                try template.quantity(value)
            }
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
        #expect(throws: HealthKitConversionError.ValueFailure.shapeInvalid) {
            try template.quantity(101)
        }
        #expect(try template.quantity(98).value?.value?.decimal == 98)
    }
}

#endif
