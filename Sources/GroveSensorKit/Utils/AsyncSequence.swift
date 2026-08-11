//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order type_name identifier_name

import Foundation


/// Builds an async iterator from an optionally conditional composition of one or more async iterators.
///
/// The primary use case here is being able to conditionally return different `AsyncIteratorProtocol` types from an `AsyncSequence`'s `makeAsyncIterator()` function,
/// without needing to resort to existentials.
@available(iOS 18.0, *)
@resultBuilder
public enum _AsyncIteratorBuilder<Element, Failure: Error> {
    // swiftlint:disable missing_docs
    @inlinable
    public static func buildExpression<I: AsyncIteratorProtocol<Element, Failure>>(_ iterator: I) -> I {
        iterator
    }
    
    @_disfavoredOverload
    @inlinable
    public static func buildExpression<S: AsyncSequence<Element, Failure>>(_ sequence: S) -> S.AsyncIterator {
        sequence.makeAsyncIterator()
    }
    
    @inlinable
    public static func buildEither<True: AsyncIteratorProtocol<Element, Failure>, False: AsyncIteratorProtocol<Element, Failure>>(
        first iterator: True
    ) -> _ConditionalAsyncIterator<True, False> {
        _ConditionalAsyncIterator<True, False>(iterator)
    }
    
    @inlinable
    public static func buildEither<True: AsyncIteratorProtocol<Element, Failure>, False: AsyncIteratorProtocol<Element, Failure>>(
        second iterator: False
    ) -> _ConditionalAsyncIterator<True, False> {
        _ConditionalAsyncIterator<True, False>(iterator)
    }
    
    @inlinable
    public static func buildBlock() -> some AsyncIteratorProtocol<Element, Failure> {
        _EmptyAsyncSequence()
    }
    
    @inlinable
    public static func buildPartialBlock<I: AsyncIteratorProtocol<Element, Failure>>(first: I) -> I {
        first
    }
    
    @inlinable
    public static func buildPartialBlock<A: AsyncIteratorProtocol<Element, Failure>, N: AsyncIteratorProtocol<Element, Failure>>(
        accumulated: A,
        next: N
    ) -> _Chain2AsyncIterator<A, N> {
        _Chain2AsyncIterator<A, N>(accumulated, next)
    }
    
    @inlinable
    public static func buildArray<I: AsyncIteratorProtocol<Element, Failure> & SendableMetatype>(
        _ components: [I]
    ) -> some AsyncIteratorProtocol<Element, Failure> {
        components
            .map { _AsyncIteratorSequence($0) }
            ._makeAsync(failureType: Failure.self)
            .flatMap { $0 }
            .makeAsyncIterator()
    }
    
    @inlinable
    public static func buildFinalResult<I: AsyncIteratorProtocol<Element, Failure>>(_ iterator: I) -> I {
        iterator
    }
    // swiftlint:enable missing_docs
}


/// An async iterator that iterates over one of two iterators.
@available(iOS 18.0, *)
public struct _ConditionalAsyncIterator<A: AsyncIteratorProtocol, B: AsyncIteratorProtocol>: AsyncIteratorProtocol
where A.Element == B.Element, A.Failure == B.Failure {
    public typealias Element = A.Element
    public typealias Failure = A.Failure
    
    @usableFromInline
    enum Storage {
        case fst(A)
        case snd(B)
    }
    
    @usableFromInline var _storage: Storage
    
    @inlinable
    init(_ base: A) {
        _storage = .fst(base)
    }
    
    @inlinable
    init(_ base: B) {
        _storage = .snd(base)
    }
    
    @inlinable
    public mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
        switch _storage {
        case .fst(var base):
            defer {
                _storage = .fst(base)
            }
            return try await base.next(isolation: actor)
        case .snd(var base):
            defer {
                _storage = .snd(base)
            }
            return try await base.next(isolation: actor)
        }
    }
    
    /// Explicit witness for the legacy `next()` requirement.
    ///
    /// Needed to work around https://github.com/swiftlang/swift/issues/87849
    /// Can be removed once the deployment target is iOS 18.4+
    @inlinable
    public mutating func next() async throws(Failure) -> Element? {
        try await next(isolation: nil)
    }
}


/// An `AsyncSequence` that contains no elements.
@available(iOS 18, *)
public struct _EmptyAsyncSequence<Element, Failure: Error>: AsyncSequence, AsyncIteratorProtocol {
    public typealias Element = Element
    public typealias Failure = Failure
    
    @inlinable
    public init() {}
    
    @inlinable
    public func makeAsyncIterator() -> some AsyncIteratorProtocol<Element, Failure> {
        self
    }
    
    @inlinable
    public func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
        nil
    }
    
    /// Explicit witness for the legacy `next()` requirement.
    ///
    /// Needed to work around https://github.com/swiftlang/swift/issues/87849
    /// Can be removed once the deployment target is iOS 18.4+
    @inlinable
    public func next() async throws(Failure) -> Element? {
        nil
    }
}


/// A concatenation of two async iterators.
@available(iOS 18, *)
public struct _Chain2AsyncIterator<A: AsyncIteratorProtocol, B: AsyncIteratorProtocol>: AsyncIteratorProtocol
where A.Element == B.Element, A.Failure == B.Failure {
    public typealias Element = A.Element
    public typealias Failure = A.Failure
    
    @usableFromInline var _fstIt: A
    @usableFromInline var _sndIt: B
    
    @inlinable
    init(_ fstIt: A, _ sndIt: B) {
        self._fstIt = fstIt
        self._sndIt = sndIt
    }
    
    @inlinable
    public mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
        if let element = try await _fstIt.next(isolation: actor) {
            element
        } else {
            try await _sndIt.next(isolation: actor)
        }
    }
    
    /// Explicit witness for the legacy `next()` requirement.
    ///
    /// Needed to work around https://github.com/swiftlang/swift/issues/87849
    /// Can be removed once the deployment target is iOS 18.4+
    @inlinable
    public mutating func next() async throws(Failure) -> Element? {
        try await next(isolation: nil)
    }
}


/// An async sequence that wraps an async iterator.
///
/// Async counterpart to Swift's `IteratorSequence`.
@available(iOS 18, *)
public struct _AsyncIteratorSequence<Base: AsyncIteratorProtocol>: AsyncSequence, AsyncIteratorProtocol {
    public typealias Element = Base.Element
    public typealias Failure = Base.Failure
    
    @usableFromInline var _base: Base
    
    @inlinable
    public init(_ base: Base) {
        _base = base
    }
    
    @inlinable
    public func makeAsyncIterator() -> some AsyncIteratorProtocol<Element, Failure> {
        self
    }
    
    @inlinable
    public mutating func next(isolation actor: isolated (any Actor)?) async throws(Base.Failure) -> Base.Element? {
        try await _base.next(isolation: actor)
    }
    
    /// Explicit witness for the legacy `next()` requirement.
    ///
    /// Needed to work around https://github.com/swiftlang/swift/issues/87849
    /// Can be removed once the deployment target is iOS 18.4+
    @inlinable
    public mutating func next() async throws(Base.Failure) -> Base.Element? {
        try await next(isolation: nil)
    }
}


extension Sequence {
    /// Creates an `AsyncSequence` that produces this sequence's elements.
    @available(iOS 18.0, *)
    @inlinable
    consuming func _makeAsync<Failure: Error>(failureType: Failure.Type = Never.self) -> some AsyncSequence<Element, Failure> {
        _AsyncSequenceAdapter<Self, Failure>(base: self)
    }
}


/// Turns a `Sequence` into an `AsyncSequence`.
@available(iOS 18.0, *)
public struct _AsyncSequenceAdapter<Base: Sequence, Failure: Error>: AsyncSequence {
    public typealias Element = Base.Element
    public typealias Failure = Failure
    
    @usableFromInline let _base: Base
    
    @inlinable
    init(base: Base) {
        self._base = base
    }
    
    @inlinable
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: _base.makeIterator())
    }
}


@available(iOS 18.0, *)
extension _AsyncSequenceAdapter {
    public struct AsyncIterator: AsyncIteratorProtocol {
        @usableFromInline var _base: Base.Iterator
        
        @inlinable
        init(base: Base.Iterator) {
            self._base = base
        }
        
        @inlinable
        public mutating func next() async throws(Failure) -> Element? {
            _base.next()
        }
    }
}
