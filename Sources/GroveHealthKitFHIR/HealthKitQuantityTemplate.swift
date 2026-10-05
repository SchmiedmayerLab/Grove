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

    /// The component carrying `value`.
    func component(_ value: Double) throws(HealthKitConversionError.ValueFailure) -> ObservationComponent {
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
    func quantity(_ value: Double) throws(HealthKitConversionError.ValueFailure) -> Quantity {
        let decimal: Decimal
        do {
            decimal = try GroveFHIRDecimal(value).decimal
        } catch {
            throw .shapeInvalid
        }
        guard domain?.contains(decimal) != false else {
            throw .shapeInvalid
        }
        var quantity = empty
        quantity.value = FHIRPrimitive(FHIRDecimal(decimal))
        return quantity
    }
}

#endif
