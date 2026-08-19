//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


enum GrovePropertyError: Error {
    case unsatisfiedStandardConstraint(constraint: String, standard: String)
}


@available(iOS 18, macOS 15, watchOS 11, *)
protocol GrovePropertyWrapper {
    /// Inject the global Grove instance.
    ///
    /// This call happens right before ``Module/configure()`` is called.
    /// An empty default implementation is provided.
    /// - Parameter grove: The global ``Grove/Grove`` instance.
    @MainActor
    func inject(grove: Grove) throws(GrovePropertyError)

    /// Clear the property wrapper state before the Module is unloaded.
    @MainActor
    func clear()
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension GrovePropertyWrapper {
    func inject(grove: Grove) {}
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Module {
    @MainActor
    func inject(grove: Grove) throws(GrovePropertyError) {
        for wrapper in retrieveProperties(ofType: (any GrovePropertyWrapper).self) {
            try wrapper.inject(grove: grove)
        }
    }

    @MainActor
    func clear() {
        for wrapper in retrieveProperties(ofType: (any GrovePropertyWrapper).self) {
            wrapper.clear()
        }
    }
}


extension GrovePropertyError: CustomStringConvertible {
    var description: String {
        switch self {
        case let .unsatisfiedStandardConstraint(constraint, standard):
                """
                The `Standard` defined in the `Configuration` does not conform to \(constraint).
                
                Ensure that you define an appropriate standard in your configuration in your `GroveAppDelegate` subclass ...
                ```
                var configuration: Configuration {
                    Configuration(standard: \(standard)()) {
                        // ...
                    }
                }
                ```
                
                ... and that your standard conforms to \(constraint):
                
                ```swift
                actor \(standard): Standard, \(constraint) {
                    // ...
                }
                ```
                """
        }
    }
}
