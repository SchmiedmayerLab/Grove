//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import ModelsR4


/// A business identifier together with the Grove role it carries in `Identifier.type`.
public struct RoledIdentifier: Hashable, Sendable {
    public let identifier: BusinessIdentifier
    public let role: GroveIdentifierRole

    public var fhirIdentifier: Identifier {
        Identifier(
            system: FHIRPrimitive(FHIRURI(stringLiteral: identifier.system.rawValue)),
            type: CodeableConcept(coding: [
                Coding(
                    code: role.rawValue.asFHIRStringPrimitive(),
                    system: Canonicals.identifierRoleCodeSystem
                )
            ]),
            value: identifier.value.asFHIRStringPrimitive()
        )
    }

    public var fullURL: FHIRPrimitive<FHIRURI> {
        get throws(ExchangeIdentityError) {
            try identifier.fullURL
        }
    }

    package var fullURLString: String {
        get throws(ExchangeIdentityError) {
            try identifier.fullURLString
        }
    }

    public init(identifier: BusinessIdentifier, role: GroveIdentifierRole) {
        self.identifier = identifier
        self.role = role
    }

    /// Reads a Grove-typed Identifier: exactly one role coding whose code the closed role set names.
    public init(_ identifier: Identifier) throws(ExchangeIdentityError) {
        let roleCodings = identifier.type?.coding?.filter {
            $0.system?.value?.url.absoluteString == Canonicals.identifierRoleCodeSystemValue
        } ?? []
        guard roleCodings.count <= 1 else {
            throw .duplicateIdentifierRole
        }
        guard let rawRole = roleCodings.first?.code?.value?.string, !rawRole.isEmpty else {
            throw .invalidIdentifierRole("missing")
        }
        guard let role = GroveIdentifierRole(rawValue: rawRole) else {
            throw .invalidIdentifierRole(rawRole)
        }
        self.init(identifier: try BusinessIdentifier(identifier), role: role)
    }
}
