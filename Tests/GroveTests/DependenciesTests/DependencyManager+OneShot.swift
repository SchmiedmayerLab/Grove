//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import Grove
import Testing


extension DependencyManager {
    static func resolve(_ modules: [any Module]) throws -> [any Module] {
        let dependencyManager = DependencyManager(modules)
        try dependencyManager.resolve()
        return dependencyManager.initializedModules
    }

    static func resolveWithoutErrors(_ modules: [any Module], file: StaticString = #filePath, line: UInt = #line) -> [any Module] {
        let dependencyManager = DependencyManager(modules)
        #expect(throws: Never.self) { try dependencyManager.resolve() }
        return dependencyManager.initializedModules
    }
}
