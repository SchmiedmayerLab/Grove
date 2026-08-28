//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import ModelsR4


/// A system-qualified physical unit for `Quantity`.
public struct FHIRQuantityUnit: Hashable, Sendable {
    public let system: FHIRPrimitive<FHIRURI>
    public let code: FHIRPrimitive<FHIRString>
    public let display: FHIRPrimitive<FHIRString>

    public init(system: FHIRPrimitive<FHIRURI>, code: String, display: String) {
        self.system = system
        self.code = code.asFHIRStringPrimitive()
        self.display = display.asFHIRStringPrimitive()
    }

    public init(
        system: FHIRPrimitive<FHIRURI>,
        code: FHIRPrimitive<FHIRString>,
        display: FHIRPrimitive<FHIRString>
    ) {
        self.system = system
        self.code = code
        self.display = display
    }

    public static func ucum(code: String, display: String? = nil) -> Self {
        Self(
            system: "http://unitsofmeasure.org",
            code: code,
            display: display ?? code
        )
    }
}


// Note: we intentionally directly use `FHIRPrimitive`s here (instead of Strings which then get converted when needed);
// the reason being that the `asFHIR{String|URI|etc}Primitive()` operations do take some time on the scale we perform them,
// and it's just way more efficient to only perform this operation once.
//
// Conforming types are strongly encouraged to define their individual codings as non-computed static properties
// to better achieve these performance improvements.
public protocol CodingProtocol: Hashable, Sendable {
    static var system: FHIRPrimitive<FHIRURI> { get }
    static var version: FHIRPrimitive<FHIRString>? { get }
    
    var code: FHIRPrimitive<FHIRString> { get }
    var display: FHIRPrimitive<FHIRString>? { get }
}


extension CodingProtocol {
    /// Two codings of one type are the same concept when they state the same code.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.code == rhs.code
    }
    
    /// Hashes the code, which is what equality compares.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(code)
    }
}

extension CodingProtocol {
    /// The terminology version, when the system pins one; most do not.
    public static var version: FHIRPrimitive<FHIRString>? {
        nil
    }
    
    /// The system this coding's type belongs to.
    public var system: FHIRPrimitive<FHIRURI> {
        Self.system
    }
    
    /// The terminology version this coding's type pins, if any.
    public var version: FHIRPrimitive<FHIRString>? {
        Self.version
    }
}


// MARK: FHIR Extensions

extension Coding {
    // periphery:ignore:parameters system
    /// Builds a Coding from a typed code, carrying its system, version, and display.
    public init<C: CodingProtocol>(system: C.Type = C.self, code: C) {
        self.init(
            code: code.code,
            display: code.display,
            system: code.system,
            version: code.version
        )
    }
}

extension CodeableConcept {
    /// Builds the concept from a typed code, carrying its system and display.
    public init<C: CodingProtocol>(system: C.Type = C.self, code: C) {
        self.init(coding: [Coding(system: system, code: code)])
    }
}


extension ObservationComponent {
    /// Builds the concept from a typed code, carrying its system and display.
    public init<C: CodingProtocol>(
        system: C.Type = C.self,
        code: C,
        value: ObservationComponent.ValueX?
    ) {
        self.init(
            code: CodeableConcept(system: system, code: code),
            value: value
        )
    }
    
    /// Builds a component whose clinical concept and physical unit remain distinct.
    public init<C: CodingProtocol>(
        system: C.Type = C.self,
        code: C,
        quantityUnit: FHIRQuantityUnit,
        quantityValue: Double
    ) {
        self.init(
            code: CodeableConcept(system: system, code: code),
            value: .quantity(Quantity(unit: quantityUnit, value: quantityValue))
        )
    }
}


extension Quantity {
    /// Builds a Quantity from a typed physical unit, never from the Observation's concept code.
    public init(unit: FHIRQuantityUnit, value: Double) {
        self.init(
            code: unit.code,
            system: unit.system,
            unit: unit.display,
            value: value.asFHIRDecimalPrimitive()
        )
    }
}
