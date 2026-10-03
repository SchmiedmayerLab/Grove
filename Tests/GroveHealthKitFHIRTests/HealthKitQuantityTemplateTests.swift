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


/// Quantity and component templates against the per-sample builders they replace.
@Suite
struct HealthKitQuantityTemplateTests {
    /// Zero, fractions, negatives, binary64 artifacts, integers, the smallest and largest finite values, and non-finite values.
    private static let values: [Double] = [
        0, -0.0, 0.5, 1.5, -1, 1e-7, 36.52, 0.1 + 0.2, 7.000000000000001, 28.199999999999996, 98, 100, 100.5, 120, 250,
        1_000, 1e21, 5e-324, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, .nan, .infinity, -.infinity
    ]

    /// Every quantity contract in both generated catalogs, measurement and component alike.
    private static let contracts: [MeasurementContract] = MeasurementCatalog.all + HealthKitMeasurementCatalog.all

    /// Whether both builders yield equal values that also print alike, or throw the same failure.
    private static func agree<Value: Equatable>(_ legacy: Result<Value, any Error>, _ kernel: Result<Value, HealthKitValueFailure>) -> Bool {
        switch (legacy, kernel) {
        case let (.success(lhs), .success(rhs)):
            lhs == rhs && String(describing: lhs) == String(describing: rhs)
        case let (.failure(lhs), .failure(rhs)):
            lhs as? HealthKitValueFailure == rhs
        default:
            false
        }
    }

    @Test("A quantity template yields the builder's quantity or its error for every contract and value")
    func quantitiesMatchTheBuilder() {
        var mismatches: [String] = []
        let quantities = Self.contracts.flatMap { contract in
            [contract.quantity].compactMap(\.self) + contract.components.compactMap(\.quantity)
        }
        for contract in quantities {
            let template = QuantityTemplate(contract)
            for value in Self.values {
                let legacy = Result { try HealthKitConverter.fhirQuantity(value: value, contract: contract) }
                let kernel = Result { () throws(HealthKitValueFailure) in try template.quantity(value) }
                if !Self.agree(legacy, kernel) {
                    mismatches.append("\(contract.code) \(value): \(legacy) != \(kernel)")
                }
            }
        }
        #expect(!quantities.isEmpty)
        #expect(mismatches.isEmpty, "\(mismatches)")
    }

    @Test("A component template yields the workout statistic builder's component for every workout component")
    func workoutComponentsMatchTheBuilder() throws {
        let components = MeasurementCatalog.workout.components.filter { $0.quantity != nil }
        #expect(!components.isEmpty)
        for component in components {
            let template = try #require(ComponentTemplate(component))
            for value in Self.values {
                let legacy = Result { try HealthKitConverter.component(component.id, value: value) }
                let kernel = Result { () throws(HealthKitValueFailure) in try template.component(value) }
                #expect(Self.agree(legacy, kernel), "\(component.id) \(value)")
            }
        }
    }

    /// The blood-pressure builder's coding, written out as it builds it, for every component with a quantity.
    @Test("A component template's code is the contract's code and system, without a display")
    func componentCodes() throws {
        for component in Self.contracts.flatMap(\.components) {
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
        #expect(throws: HealthKitValueFailure.shapeInvalid) {
            try template.quantity(101)
        }
        #expect(try template.quantity(98).value?.value?.decimal == 98)
    }
}

#endif
