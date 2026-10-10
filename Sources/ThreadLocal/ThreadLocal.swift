//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable type_name identifier_name

public import Foundation
#if os(Linux)
import Glibc
#else
import Darwin.C
#endif


/// Manages a thread-local defined via the ``ThreadLocal()`` macro.
///
/// You do not use this type directly.
/// Instead, your code interacts with thread-local variables by simply directly accessing them via their getter and setter.
///
/// Each thread's value lives in a box its pthread slot owns: the thread's first read stores the default there, a write
/// replaces the value in the box, and the thread's exit releases the box, which hands its value to the deallocator.
public final class ThreadLocal<Value>: Sendable {
    @usableFromInline let _key: pthread_key_t
    @usableFromInline let _deallocator: Deallocator

    /// The calling thread's box, or `nil` until the thread first reads or writes the value.
    @inlinable var _box: _Box? {
        pthread_getspecific(_key).map {
            Unmanaged<_Box>.fromOpaque($0).takeUnretainedValue()
        }
    }

    @available(*, noasync)
    public init(_deallocator deallocator: Deallocator = .default) {
        var key = pthread_key_t()
        #if os(Linux)
        let destroyFn: @convention(c) (UnsafeMutableRawPointer?) -> Void = { ptr in
            if let ptr {
                Unmanaged<AnyObject>.fromOpaque(ptr).release()
            }
        }
        #else
        let destroyFn: @convention(c) (UnsafeMutableRawPointer) -> Void = { ptr in
            Unmanaged<AnyObject>.fromOpaque(ptr).release()
        }
        #endif
        let status = pthread_key_create(&key, destroyFn)
        precondition(status == 0, "pthread_key_create failed with status code \(status)")
        _key = key
        _deallocator = deallocator
    }

    /// The calling thread's value, after storing `default` if the thread has none yet.
    @available(*, noasync)
    @inlinable
    public func _get(default: @autoclosure () -> Value) -> Value {
        if let box = _box {
            return box._value
        }
        let value = `default`()
        _set(value)
        return value
    }

    /// Stores `newValue` as the calling thread's value; the value it replaces goes to the deallocator.
    @available(*, noasync)
    @inlinable
    public func _set(_ newValue: Value) {
        if let box = _box {
            box._value = newValue
        } else {
            let unmanaged = Unmanaged.passRetained(_Box(_value: newValue, deallocator: _deallocator))
            let status = pthread_setspecific(_key, unmanaged.toOpaque())
            precondition(status == 0, "pthread_setspecific failed with status code \(status)")
        }
    }

    deinit {
        pthread_key_delete(_key)
    }
}


extension ThreadLocal {
    /// Controls how a value managed by ``ThreadLocal`` is deallocated.
    ///
    /// ## Topics
    /// ### Deallocator Types
    /// - ``default``
    /// - ``free``
    /// - ``custom(_:)``
    public struct Deallocator: Sendable {
        public let _imp: (@Sendable (Value) -> Void)?

        @inlinable
        public init(_imp: (@Sendable (Value) -> Void)?) {
            self._imp = _imp
        }
    }
}

extension ThreadLocal.Deallocator {
    /// The default deallocator, which matches Swift's default semantics.
    ///
    /// - Note: This deallocator should be used for all "regular" Swift types, e.g. structs, classes, closures, etc.
    @inlinable public static var `default`: Self {
        Self(_imp: nil)
    }

    /// A deallocator which uses a custom closure to deallocate a value.
    @inlinable
    public static func custom(_ imp: @escaping @Sendable (Value) -> some Any) -> Self {
        Self {
            _ = imp($0)
        }
    }
}

extension ThreadLocal.Deallocator where Value: _Pointer & SendableMetatype {
    /// A deallocator which `free`s a pointer value.
    @inlinable public static var free: Self {
        Self { Foundation.free(unsafeBitCast($0, to: UnsafeMutableRawPointer.self)) }
    }
}


extension ThreadLocal {
    /// One thread's value, owned by that thread's slot.
    public final class _Box {
        /// The thread's value; the one a write replaces goes to ``_deallocator``.
        public var _value: Value {
            didSet {
                _deallocator._imp?(oldValue)
            }
        }

        /// Called with the box's value when it is replaced and when the box is released.
        public let _deallocator: Deallocator

        /// A box holding `value`.
        @inlinable
        public init(_value value: Value, deallocator: Deallocator) {
            self._value = value
            self._deallocator = deallocator
        }

        @inlinable
        deinit {
            _deallocator._imp?(_value)
        }
    }
}
