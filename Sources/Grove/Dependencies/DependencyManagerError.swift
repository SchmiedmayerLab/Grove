//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


enum DependencyManagerError: Error {
    case searchStackCycle(module: String, requestedModule: String, dependencyChain: [String])
    case missingRequiredModule(module: String, requiredModule: String)
}


extension DependencyManagerError: CustomStringConvertible {
    var description: String {
        switch self {
        case let .searchStackCycle(module, requestedModule, dependencyChain):
            """
            The `DependencyManager` has detected a dependency cycle of your Grove modules.
            The current dependency chain is: \(dependencyChain.joined(separator: ", ")). \
            The module '\(module)' required '\(requestedModule)' which is contained in its own dependency chain.
            
            Please ensure that the modules you use or develop can not trigger a dependency cycle.
            """
        case let .missingRequiredModule(module, requiredModule):
            """
            '\(module) requires dependency of type '\(requiredModule)' which wasn't configured.
            Please make sure this module is configured by including it in the configuration of your `GroveAppDelegate` or following \
            Module-specific instructions.
            """
        }
    }
}
