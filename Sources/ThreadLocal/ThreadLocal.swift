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
public final class ThreadLocal<Value>: Sendable {
    nonisolated(unsafe) public private(set) var _key: pthread_key_t
    public let _deallocator: Deallocator

    @inlinable var _box: _Box? {
        guard let ptr = pthread_getspecific(_key) else {
            return nil
        }
        let unmanaged = Unmanaged<_Box>.fromOpaque(ptr)
        return unmanaged.takeUnretainedValue()
    }

    @available(*, noasync)
    public init(_deallocator deallocator: Deallocator = .default) {
        _key = pthread_key_t()
        _deallocator = deallocator
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
        let status = pthread_key_create(&_key, destroyFn)
        precondition(status == 0, "pthread_key_create failed with status code \(status)")
    }

    @available(*, noasync)
    @inlinable
    func _makeBox(_ value: Value) -> _Box {
        _Box(_value: value, deallocator: _deallocator)
    }

    @available(*, noasync)
    @inlinable
    public func _get(default: @autoclosure () -> Value) -> Value {
        if let value = _box?._value {
            return value
        } else {
            let value = `default`()
            _set(value)
            return value
        }
    }

    @available(*, noasync)
    @inlinable
    public func _set(_ newValue: Value?) {
        let unmanaged = pthread_getspecific(_key).map {
            Unmanaged<_Box>.fromOpaque($0)
        }
        guard let newValue else {
            pthread_setspecific(_key, nil)
            unmanaged?.release()
            return
        }
        if let unmanaged {
            unmanaged.takeUnretainedValue()._value = newValue
        } else {
            let unmanaged = Unmanaged.passRetained(_makeBox(newValue))
            pthread_setspecific(_key, unmanaged.toOpaque())
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
    public final class _Box: AnyObject {
        public var _value: Value? {
            didSet {
                if let oldValue {
                    _deallocator._imp?(oldValue)
                }
            }
        }

        public let _deallocator: Deallocator

        @inlinable
        public init(_value value: Value, deallocator: Deallocator) {
            self._value = value
            self._deallocator = deallocator
        }

        @inlinable
        deinit {
            if let _value {
                _deallocator._imp?(_value)
            }
        }
    }
}
