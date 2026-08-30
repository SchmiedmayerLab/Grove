//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import ModelsR4


extension BusinessIdentifier {
    /// Creates an identifier-only logical Reference with an explicit target resource type.
    ///
    /// Grove conversion contexts use this shape when the referenced resource does not travel in
    /// the same Bundle. Literal references remain reserved for resolvable Bundle entries.
    public func reference(to resourceType: ResourceType) -> Reference {
        Reference(
            identifier: fhirIdentifier,
            type: FHIRPrimitive(FHIRURI(stringLiteral: resourceType.rawValue))
        )
    }
}
