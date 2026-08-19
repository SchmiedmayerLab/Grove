//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import ModelsR4


/// Type-erased version of a ``FHIRExtensionBuilder``
public protocol FHIRExtensionBuilderProtocol<Input>: Sendable {
    /// The extension builder's input type.
    associatedtype Input
    
    /// Applies the extension builder to an `any FHIRTypeWithExtensions`, using the specified input.
    func apply(input: Input, to resource: inout some FHIRTypeWithExtensions) throws
}


/// Defines a custom Extension Builder that can be applied to a FHIR `any FHIRTypeWithExtensions` representing a HeathKit sample.
///
/// ## Topics
///
/// ### Creating an Extension Builder
/// - ``init(_:)-((Input,FHIRTypeWithExtensions)->Void)``
/// - ``init(_:)-((FHIRTypeWithExtensions)->Void)``
///
/// ### Applying Extensions
/// - ``apply(input:to:)``
/// - ``apply(to:)``
/// - ``apply(typeErasedInput:to:)``
///
/// ### Supporting Types
/// - ``FHIRExtensionURL``
/// - ``FHIRExtensionBuilderProtocol``
///
/// ### Other
/// - ``FHIRTypeWithExtensions/apply(_:input:)``
/// - ``FHIRTypeWithExtensions/apply(_:)``
public struct FHIRExtensionBuilder<Input>: FHIRExtensionBuilderProtocol, Sendable {
    private let impl: @Sendable (_ input: Input, _ resource: inout any FHIRTypeWithExtensions) throws -> Void
    
    /// Creates an Extension Builder.
    public init(_ action: @escaping @Sendable (_ input: Input, _ resource: inout any FHIRTypeWithExtensions) throws -> Void) {
        self.impl = action
    }
    
    /// Creates an Extension Builder.
    public init(_ action: @escaping @Sendable (_ resource: inout any FHIRTypeWithExtensions) throws -> Void) where Input == Void {
        self.init { _, resource in
            try action(&resource)
        }
    }
    
    /// Applies an extension builder to an input.
    public func apply<T: FHIRTypeWithExtensions>(input: Input, to resource: inout T) throws {
        var copy: any FHIRTypeWithExtensions = resource
        try impl(input, &copy)
        guard let copy = copy as? T else {
            preconditionFailure("Extension builder ilegally changed resource type!")
        }
        resource = copy
    }
}


extension FHIRExtensionBuilderProtocol {
    /// Applies the extension builder to an `any FHIRTypeWithExtensions`.
    public func apply(to resource: inout some FHIRTypeWithExtensions) throws where Input == Void {
        try apply(input: (), to: &resource)
    }
    
    /// Attempts to apply the extension builder to an `any FHIRTypeWithExtensions`, using the specified input.
    ///
    /// This function will have no effect if `typeErasedInput` doesn't match the extension builder's input type.
    /// An exception is if the extension builder's input type is `Void`; in this case any input is allowed, and will simply be discarded.
    ///
    /// - returns: A boolean value indicating whether the input was able to be coerced to the expected input type, and the builder was invoked.
    @available(iOS 18, macOS 15, watchOS 11, *)
    @discardableResult
    public func apply(typeErasedInput input: Any, to resource: inout some FHIRTypeWithExtensions) throws -> Bool {
        if let input = input as? Input {
            try apply(input: input, to: &resource)
            return true
        } else if let self = self as? any FHIRExtensionBuilderProtocol<Void> {
            // if the extension builder takes Void
            try self.apply(to: &resource)
            return true
        } else {
            return false
        }
    }
}


extension FHIRTypeWithExtensions {
    /// Applies a ``FHIRExtensionBuilder`` to the `any FHIRTypeWithExtensions`.
    public mutating func apply(_ builder: FHIRExtensionBuilder<Void>) throws {
        try builder.apply(to: &self)
    }
    
    /// Applies a ``FHIRExtensionBuilder`` to the `any FHIRTypeWithExtensions`.
    public mutating func apply<Input>(_ builder: FHIRExtensionBuilder<Input>, input: Input) throws {
        try builder.apply(input: input, to: &self)
    }
}
