//
// This source file is part of the Stanford Spezi open-source project
// It is based on the code from the Apodini (https://github.com/Apodini/Apodini) project.
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md) and the Apodini project authors
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable syntactic_sugar type_contents_order


/// A type erased `Optional`.
///
/// This is useful to unwrapping, e.g.,  generics or associated types by declaring an extension under the condition of
/// ``AnyOptional`` conformance. This allows in the implementation of the extension to access the underlying
/// ``Wrapped`` type of an `Optional`, essentially unwrapping the optional type.
///
/// ``AnyOptional`` conforms to the [`ExpressibleByNilLiteral`](https://developer.apple.com/documentation/swift/expressiblebynilliteral) protocol.
/// Apple states that only the `Optional` type conforms to `ExpressibleByNilLiteral`. `ExpressibleByNilLiteral` conformance for types that use `nil for other purposes is discouraged.
public protocol AnyOptional: ExpressibleByNilLiteral {
    /// The underlying type of the Optional
    associatedtype Wrapped
    
    /// Constructs an empty instance of the Optional.
    static var none: Self { get }
    
    /// Constructs a non-empty empty instance of the Optional.
    static func some(_ wrapped: Wrapped) -> Self
    
    /// This property provides access to the underlying Optional
    var unwrappedOptional: Optional<Wrapped> { get }
}


extension Optional: AnyOptional {
    public var unwrappedOptional: Optional<Wrapped> {
        self
    }
}
