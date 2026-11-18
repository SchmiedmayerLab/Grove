//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import ModelsR4


/// The selection facts of one generated measurement; complete FHIR validation remains the guide's responsibility.
public struct FHIRMeasurementDefinition: Sendable {
    /// The effective-time datatypes a measurement admits.
    public enum Effective: Sendable, Equatable {
        /// A point in time.
        case dateTime
        /// A whole interval.
        case period
        /// Either datatype; a collection adapter still selects its own source's semantics.
        case dateTimeOrPeriod
    }

    /// The value shape the generated quantity, coded-result or component facts describe.
    public enum ValueShape: Sendable, Equatable {
        /// A top-level Quantity, possibly accompanied by components.
        case quantity
        /// A top-level CodeableConcept, possibly accompanied by components.
        case coded
        /// Components without a top-level quantity or coded result.
        case components
    }

    /// An exact coding from the generated contract.
    public struct Code: Sendable, Equatable {
        /// The coding system URI.
        public let system: String
        /// The case-sensitive code.
        public let value: String

        package init(_ coding: CodingContract) {
            system = coding.system
            value = coding.code
        }
    }

    /// The canonical unit of a generated quantity.
    public struct Quantity: Sendable, Equatable {
        /// The unit system URI.
        public let system: String
        /// The machine-readable unit code, generally UCUM.
        public let code: String

        package init(_ quantity: QuantityContract) {
            system = quantity.system
            code = quantity.code
        }
    }

    /// A component's identity and its quantity or coded-result family.
    public struct Component: Sendable {
        /// The component's catalog identifier.
        public let id: String
        /// The exact component coding.
        public let code: Code
        /// The canonical unit, when the component is quantitative.
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

    /// The exact measurement identifier.
    public let id: String
    /// The measurement's direct canonical profile.
    public let profile: FHIRPrimitive<Canonical>
    /// The primary measurement coding.
    public let code: Code
    /// The codings required beside the primary code; translations still follow the profile.
    public let requiredCodings: [Code]
    /// The admitted effective-time datatypes, without inferring a source query predicate.
    public let effective: Effective
    /// The generated value shape, or `nil` when these descriptors don't express the measurement's value datatype.
    ///
    /// A missing shape doesn't admit an arbitrary FHIR value or establish producer support.
    public let valueShape: ValueShape?
    /// The canonical unit of the top-level quantity, when present.
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
