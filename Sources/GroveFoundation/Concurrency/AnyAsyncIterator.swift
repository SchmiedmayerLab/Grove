//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// A type-erased async iterator.
public struct AnyAsyncIterator<Element, Failure: Error>: AsyncIteratorProtocol {
    @usableFromInline var base: any AsyncIteratorProtocol
    
    /// Creates an async iterator that wraps a base iterator but whose type depends only on the base iterator's `Element` and `Failure` types.
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @inlinable
    public init(_ base: some AsyncIteratorProtocol<Element, Failure>) {
        self.base = base
    }
    
    /// Creates an async iterator that wraps a base iterator but whose type depends only on the base iterator's `Element` type.
    @_disfavoredOverload
    @inlinable
    public init<I: AsyncIteratorProtocol>(_ base: I) where I.Element == Element, Failure == any Error {
        self.base = base
    }
    
    /// Creates an async iterator that wraps a base iterator but whose type depends only on the base iterator's `Element` type, and assumes it will never throw.
    ///
    /// This initializer will forcibly coerce the input iterator into one of a type whose `Failure` is `Never`.
    /// If the iterator does in fact end up throwing an error, that is a programmer error and will result in the program getting terminated.
    ///
    /// - Note: Use this initializer in pre-iOS 18 situations, where `AsyncIteratorProtocol`'s `Failure` type isn't yet available.
    @inlinable
    public init<I: AsyncIteratorProtocol>(unsafelyAssumingDoesntThrow base: I) where I.Element == Element, Failure == Never {
        self.base = base
    }
    
    @inlinable
    public mutating func next() async throws -> Element? {
        try await base.next() as? Element
    }
    
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @inlinable
    public mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
        do {
            return try await base.next(isolation: actor) as? Element
        } catch {
            // SAFETY: our initializers only allow creating `AnyAsyncIterator`s with a matching `Failure` type
            throw error as! Failure // swiftlint:disable:this force_cast
        }
    }
}
