//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Access a property or action of the Grove application.
@available(iOS 18, macOS 15, watchOS 11, *)
@propertyWrapper
public struct _ApplicationPropertyWrapper<Value> { // swiftlint:disable:this type_name
    private final class State {
        weak var grove: Grove?
        /// Some KeyPaths are declared to copy the value upon injection and not query them every time.
        var shadowCopy: Value?
    }

    private let keyPath: KeyPath<Grove, Value>
    private let state = State()


    /// Access the application property.
    public var wrappedValue: Value {
        if let shadowCopy = state.shadowCopy {
            return shadowCopy
        }

        guard let grove = state.grove else {
            preconditionFailure("Underlying Grove instance was not yet injected. @Application cannot be accessed within the initializer!")
        }
        return grove[keyPath: keyPath]
    }

    /// Initialize a new `@Application` property wrapper
    /// - Parameter keyPath: The property to access.
    public init(_ keyPath: KeyPath<Grove, Value>) {
        self.keyPath = keyPath
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension _ApplicationPropertyWrapper: GrovePropertyWrapper {
    func inject(grove: Grove) {
        state.grove = grove
        if grove.createsCopy(keyPath) {
            state.shadowCopy = grove[keyPath: keyPath]
        }
    }

    func clear() {
        state.grove = nil
        // we do not clear the shadow copy to make sure the property wrapper stays accessible in cleanup scenarios
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Module {
    /// Access a property or action of the application.
    ///
    /// The `@Application` property wrapper can be used inside your `Module` to
    /// access a property or action of your application.
    ///
    /// - Note: You can access the contents of `@Application` once your ``Module/configure()`` method is called
    ///     (e.g., it must not be used in the `init`).
    ///
    /// Below is a short code example:
    ///
    /// ```swift
    /// class ExampleModule: Module {
    ///     @Application(\.logger)
    ///     var logger
    ///
    ///     func configure() {
    ///         logger.info("Module is being configured ...")
    ///     }
    /// }
    /// ```
    public typealias Application<Value> = _ApplicationPropertyWrapper<Value>
}
