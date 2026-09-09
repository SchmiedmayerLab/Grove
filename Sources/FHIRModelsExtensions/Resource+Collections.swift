//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension Observation {
    /// Appends an `Identifier` to the `Observation`
    public mutating func append(identifier: Identifier) {
        append(identifier, to: \.identifier)
    }
    
    /// Appends multiple `Identifier`s to the `Observation`
    public mutating func append(identifiers: some Collection<Identifier>) {
        append(identifiers, to: \.identifier)
    }
    
    /// Appends a `CodeableConcept` to the `Observation`
    public mutating func append(category: CodeableConcept) {
        append(category, to: \.category)
    }
    
    /// Appends multiple `CodeableConcept`s to the `Observation`
    public mutating func append(categories: some Collection<CodeableConcept>) {
        append(categories, to: \.category)
    }
    
    /// Appends a `Coding` to the `Observation`
    public mutating func append(coding: Coding) {
        append(coding, to: \.code.coding)
    }
    
    /// Appends multiple `Coding`s to the `Observation`
    public mutating func append(codings: some Collection<Coding>) {
        append(codings, to: \.code.coding)
    }
    
    /// Appends an `ObservationComponent` to the `Observation`
    public mutating func append(component: ObservationComponent) {
        append(component, to: \.component)
    }
    
    /// Appends multiple `ObservationComponent`s to the `Observation`
    public mutating func append(components: some Collection<ObservationComponent>) {
        append(components, to: \.component)
    }
}
