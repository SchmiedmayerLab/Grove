//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


@available(iOS 18, macOS 15, watchOS 11, *)
extension Module {
    func dependencyRelation(to module: DependencyReference) -> DependencyRelation {
        let relations = dependencyDeclarations.map { $0.dependencyRelation(to: module) }

        if relations.contains(.dependent) {
            return .dependent
        } else if relations.contains(.optional) {
            return .optional
        } else {
            return .unrelated
        }
    }
}
