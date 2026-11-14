//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import ModelsR4


/// The selection facts of one generated measurement; complete FHIR validation remains the guide's responsibility.
public struct FHIRMeasurementDefinition: Sendable {
    /// The effective-time datatypes this measurement admits.
    public enum Effective: Sendable, Equatable {
        /// A point in time.
        case dateTime
        /// A whole interval.
        case period
        /// Either datatype; a collection adapter must still select its own source's semantics.
        case dateTimeOrPeriod
    }

    /// A value shape represented by the generated quantity, coded-result or component facts.
    public enum ValueShape: Sendable, Equatable {
        /// A top-level Quantity, possibly accompanied by components.
        case quantity
        /// A top-level CodeableConcept, possibly accompanied by components.
        case coded
        /// Components without a top-level quantity or coded result.
        case components
    }

    /// The exact measurement identifier.
    public let id: String
    /// The measurement's direct canonical profile.
    public let profile: FHIRPrimitive<Canonical>
    /// The primary measurement coding.
    public let code: Code
    /// Additional codings required beside the primary code; translations still follow the profile.
    public let requiredCodings: [Code]
    /// Effective-time datatypes, without inferring a source query predicate.
    public let effective: Effective
    /// The generated value shape, or `nil` when these descriptors do not express the measurement's value datatype.
    /// A missing shape does not admit an arbitrary FHIR value or establish producer support.
    public let valueShape: ValueShape?
    /// The top-level quantity contract, when present.
    public let quantity: Quantity?
    /// The primary coded-result system, when the generated measurement declares one.
    public let resultCodeSystem: String?
    /// Every generated component, in contract order.
    public let components: [Component]

    package init(_ contract: MeasurementContract) {
        id = contract.id
        profile = contract.profile
        code = Code(contract.code)
        requiredCodings = contract.requiredCodings.map(Code.init)
        effective = switch contract.effective {
        case .dateTime: .dateTime
        case .period: .period
        case .dateTimeOrPeriod: .dateTimeOrPeriod
        }
        quantity = contract.quantity.map(Quantity.init)
        resultCodeSystem = contract.resultCodeSystem
        components = contract.components.map(Component.init)
        if contract.quantity != nil {
            valueShape = .quantity
        } else if contract.resultCodeSystem != nil {
            valueShape = .coded
        } else {
            valueShape = contract.components.isEmpty ? nil : .components
        }
    }
}


extension FHIRMeasurementDefinition {
    /// An exact coding from the generated contract.
    public struct Code: Sendable, Equatable {
        /// Coding system URI.
        public let system: String
        /// Case-sensitive code.
        public let value: String
        /// The guide's optional display text.
        public let display: String?

        package init(_ coding: CodingContract) {
            system = coding.system
            value = coding.code
            display = coding.display
        }
    }

    /// One generated quantity's canonical unit and optional numeric-domain restriction.
    public struct Quantity: Sendable, Equatable {
        /// Unit system URI.
        public let system: String
        /// Machine-readable unit code, generally UCUM.
        public let code: String
        /// Display unit; it need not equal the code.
        public let unit: String
        /// The declared numeric domain, or `nil` when this generated contract declares none.
        public let domain: Domain?

        package init(_ quantity: QuantityContract) {
            system = quantity.system
            code = quantity.code
            unit = quantity.unit
            domain = quantity.valueDomain.map(Domain.init)
        }
    }

    /// The closed numeric domain declared for a quantity; it does not replace validation of the full resource.
    public struct Domain: Sendable, Equatable {
        /// Lower bound, including whether equality is admitted.
        public let minimum: Boundary
        /// Upper bound, if declared.
        public let maximum: Boundary?
        /// Whether only whole-number values are admitted.
        public let integerOnly: Bool

        package init(_ domain: QuantityValueDomain) {
            minimum = Boundary(domain.minimum)
            maximum = domain.maximum.map(Boundary.init)
            integerOnly = domain.integerOnly
        }
    }

    /// An exact decimal bound, without conversion to binary floating point.
    public struct Boundary: Sendable, Equatable {
        /// Bound value.
        public let value: Decimal
        /// Whether equality satisfies the bound.
        public let inclusive: Bool

        package init(_ boundary: QuantityBoundary) {
            value = boundary.value
            inclusive = boundary.inclusive
        }
    }

    /// A component's identity and declared quantity or coded-result family.
    public struct Component: Sendable {
        /// The component's catalog identifier.
        public let id: String
        /// The exact component coding.
        public let code: Code
        /// The quantity unit and domain when this component is quantitative.
        public let quantity: Quantity?
        /// The primary coded-result system, when present.
        public let resultCodeSystem: String?

        package init(_ component: ComponentContract) {
            id = component.id
            code = Code(CodingContract(system: component.system, code: component.code))
            quantity = component.quantity.map(Quantity.init)
            resultCodeSystem = component.resultCodeSystem
        }
    }
}
