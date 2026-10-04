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
import ModelsR4


/// A contract component whose value is a quantity, built once: its code and its quantity template.
@available(iOS 18, macOS 15, watchOS 11, *)
struct ComponentTemplate: Sendable {
    /// The component code, one coding without a display.
    let code: CodeableConcept
    /// The component's quantity.
    let quantity: QuantityTemplate

    /// The template for a quantity component, or `nil` when the contract states no quantity for it.
    init?(_ contract: ComponentContract) {
        guard let quantity = contract.quantity else {
            return nil
        }
        code = CodeableConcept(coding: [Coding(contract.code, system: contract.system)])
        self.quantity = QuantityTemplate(quantity)
    }

    /// The component carrying `value`; it fails as ``QuantityTemplate/quantity(_:)`` does.
    func component(_ value: Double) throws -> ObservationComponent {
        ObservationComponent(code: code, value: .quantity(try quantity.quantity(value)))
    }
}


/// A contract's FHIR quantity built once, so each sample sets only the value.
@available(iOS 18, macOS 15, watchOS 11, *)
struct QuantityTemplate: Sendable {
    /// The contract's code, system and unit, with no value.
    let empty: Quantity
    /// The inclusive value domain the canonical value must fall in, if the contract states one.
    let domain: QuantityValueDomain?

    /// The template for one quantity contract.
    init(_ contract: QuantityContract) {
        empty = Quantity(
            code: contract.code.asFHIRStringPrimitive(),
            system: FHIRPrimitive(FHIRURI(stringLiteral: contract.system)),
            unit: contract.unit.asFHIRStringPrimitive()
        )
        domain = contract.valueDomain
    }

    /// The quantity carrying `value` as its shortest round-trip decimal, which must lie in the domain.
    ///
    /// A nonfinite value, or one the domain excludes, throws `HealthKitConversionError.ValueFailure.outsideDomain`. A
    /// finite value the R4 decimal model cannot hold (Foundation's `Decimal` spans fewer exponents than binary64)
    /// rethrows its `GroveFHIRDecimalError` unless the domain excludes it anyway: no registered rule names that
    /// reason, so the conversion reports it unclassified.
    func quantity(_ value: Double) throws -> Quantity {
        let decimal: Decimal
        do throws(GroveFHIRDecimalError) {
            decimal = try GroveFHIRDecimal(value).decimal
        } catch .nonFinite {
            throw HealthKitConversionError.ValueFailure.outsideDomain
        } catch {
            guard let domain, domain.excludes(binary64: value) else {
                throw error
            }
            throw HealthKitConversionError.ValueFailure.outsideDomain
        }
        guard domain?.contains(decimal) != false else {
            throw HealthKitConversionError.ValueFailure.outsideDomain
        }
        var quantity = empty
        quantity.value = FHIRPrimitive(FHIRDecimal(decimal))
        return quantity
    }
}


extension QuantityValueDomain {
    /// Whether the domain excludes a finite binary64 that has no `Decimal`: fractional where only integers are
    /// admitted, or beyond a bound. Compared in binary64, which is exact as every generated bound is exact there
    /// (`HealthKitQuantityTemplateTests` pins it); a bound that did not parse would exclude nothing.
    fileprivate func excludes(binary64 value: Double) -> Bool {
        let bound = { (boundary: QuantityBoundary) in Double(boundary.value.description) ?? .nan }
        if integerOnly, value.rounded(.towardZero) != value {
            return true
        }
        if minimum.inclusive ? value < bound(minimum) : value <= bound(minimum) {
            return true
        }
        guard let maximum else {
            return false
        }
        return maximum.inclusive ? value > bound(maximum) : value >= bound(maximum)
    }
}

#endif
