//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
#if canImport(Glibc)
import Glibc
#endif


/// One `Value` per thread, made on the thread's first ``current`` and released when the thread exits.
///
/// A cache kept this way is read and filled without a lock, so the child tasks of a concurrent build never wait for
/// each other on it, and what one thread caches is never retained or released by another.
package final class PerThread<Value: AnyObject>: Sendable {
    private let key: pthread_key_t
    private let make: @Sendable () -> Value

    /// The calling thread's value.
    package var current: Value {
        if let pointer = pthread_getspecific(key) {
            return Unmanaged<Value>.fromOpaque(pointer).takeUnretainedValue()
        }
        let value = make()
        pthread_setspecific(key, Unmanaged.passRetained(value).toOpaque())
        return value
    }

    package init(_ make: @escaping @Sendable () -> Value) {
        var key = pthread_key_t()
        #if canImport(Glibc)
        let status = pthread_key_create(&key) { $0.map { Unmanaged<AnyObject>.fromOpaque($0).release() } }
        #else
        let status = pthread_key_create(&key) { Unmanaged<AnyObject>.fromOpaque($0).release() }
        #endif
        precondition(status == 0, "pthread_key_create failed with \(status)")
        self.key = key
        self.make = make
    }

    deinit {
        pthread_key_delete(key)
    }
}
