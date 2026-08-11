//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(SwiftUI)
public import SwiftUI


/// Refer to the documentation of ``Module/Model``.
@available(iOS 18, macOS 15, watchOS 11, *)
@propertyWrapper
public class _ModelPropertyWrapper<Model: Observable & AnyObject> {
    // swiftlint:disable:previous type_name
    // We want the type to be hidden from autocompletion and documentation generation

    let id = UUID()
    private var storedValue: Model?
    private var collected = false

    private weak var grove: Grove?


    /// Access the store model.
    ///
    /// - Note: You cannot access the value once it was collected.
    public var wrappedValue: Model {
        get {
            guard let storedValue else {
                preconditionFailure("@Model was accessed before it was initialized for the first time.")
            }
            return storedValue
        }
        set {
            precondition(!collected, "You cannot reassign a @Model property after it was already collected.")
            storedValue = newValue
        }
    }


    /// Initialize a new `@Model` property wrapper.
    public init() {}

    /// Initialize a new `@Model` property wrapper.
    /// - Parameter wrappedValue: The initial value.
    public init(wrappedValue: Model) {
        self.storedValue = wrappedValue
    }


    deinit {
        // mirrors implementation of clear, however in a compiler proven, concurrency safe way (:
        collected = false
        Task { @MainActor [grove, id] in
            grove?.handleViewModifierRemoval(for: id)
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension _ModelPropertyWrapper: GrovePropertyWrapper {
    func clear() {
        collected = false
        grove?.handleViewModifierRemoval(for: id)
    }


    func inject(grove: Grove) {
        self.grove = grove
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Module {
    /// Places an observable object in the global view environment.
    ///
    /// The `@Model` property wrapper can be used inside your `Module` to place an
    /// observable model type into the global SwiftUI view environment.
    ///
    /// - Note: The contents of the `@Model` property wrapper are collected after the ``Module/configure()-5pa83`` call returns.
    ///     After collection, the model instance passed to `@Model` cannot be changed again.
    ///
    /// Below is a short code example:
    /// ```swift
    /// @Observable
    /// class ExampleModel {
    ///     var someState: Bool = false
    ///
    ///     init() {}
    /// }
    ///
    /// class ExampleModule: Module {
    ///     @Model var model = ExampleModel()
    /// }
    /// ```
    ///
    /// - Note: It is guaranteed that all observable objects placed into the environment using `@Model`
    ///     are available in all `ViewModifier`s created using the `@Modifier` property wrapper.
    public typealias Model = _ModelPropertyWrapper
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension _ModelPropertyWrapper: ViewModifierProvider {
    var viewModifier: (any ViewModifier)? {
        collected = true

        guard let storedValue else {
            assertionFailure("@Model with type \(Model.self) was collected but no value was provided!")
            return nil
        }

        return ModelModifier(model: storedValue)
    }

    var placement: ModifierPlacement {
        .outermost
    }
}
#endif
