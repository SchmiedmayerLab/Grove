//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// A type-erased wrapper over an `AsyncSequence`.
public struct AnyAsyncSequence<Element, Failure: Error>: AsyncSequence {
    @usableFromInline let makeIterator: () -> AnyAsyncIterator<Element, Failure>
    
    /// Creates an `AnyAsyncSequence` that wraps the given `AsyncSequence`
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @inlinable
    public init(_ base: some AsyncSequence<Element, Failure>) {
        makeIterator = {
            AnyAsyncIterator(base.makeAsyncIterator())
        }
    }
    
    /// Creates an `AnyAsyncSequence` that wraps the given `AsyncSequence`
    @_disfavoredOverload
    @inlinable
    public init<S: AsyncSequence>(_ base: S) where S.Element == Element, Failure == any Error {
        makeIterator = {
            AnyAsyncIterator(base.makeAsyncIterator())
        }
    }
    
    /// Creates an `AnyAsyncSequence` that wraps the given `AsyncSequence` and assumes it will never throw.
    ///
    /// This initializer will forcibly coerce the input sequence into one of a type whose `Failure` is `Never`.
    /// If the sequence does in fact end up throwing an error, that is a programmer error and will result in the program getting terminated.
    ///
    /// - Note: Use this initializer in pre-iOS 18 situations, where `AsyncSequence`'s `Failure` type isn't yet available.
    @inlinable
    public init<S: AsyncSequence>(unsafelyAssumingDoesntThrow base: S) where S.Element == Element, Failure == Never {
        makeIterator = {
            AnyAsyncIterator(unsafelyAssumingDoesntThrow: base.makeAsyncIterator())
        }
    }
    
    @inlinable
    public func makeAsyncIterator() -> AnyAsyncIterator<Element, Failure> {
        makeIterator()
    }
}
