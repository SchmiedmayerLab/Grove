//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(pthread)
public import pthread
#elseif canImport(Glibc)
public import Glibc
#else
#error("Unsupported platform: neither pthread nor Glibc is available")
#endif


@_documentation(visibility: internal)
public protocol _PThreadReadWriteLockProtocol: AnyObject, Sendable, SendableMetatype { // swiftlint:disable:this type_name
    // We need the unsafe mutable pointer, as otherwise we need to pass the property as inout parameter which isn't thread safe.
    var _rwLock: UnsafeMutablePointer<pthread_rwlock_t> { get } // swiftlint:disable:this identifier_name
    
    /// Call `body` with a reading lock.
    ///
    /// - Parameter body: A function that reads a value while locked.
    /// - Returns: The value returned from the given function.
    @inlinable
    @inline(__always)
    func withReadLock<Result, E>(_ body: () throws(E) -> Result) throws(E) -> Result
    
    /// Call `body` with a writing lock.
    ///
    /// - Parameter body: A function that writes a value while locked, then returns some value.
    /// - Returns: The value returned from the given function.
    @inlinable
    @inline(__always)
    func withWriteLock<Result, E>(_ body: () throws(E) -> Result) throws(E) -> Result
}


extension _PThreadReadWriteLockProtocol {
    static func pthreadInit() -> UnsafeMutablePointer<pthread_rwlock_t> {
        let lock: UnsafeMutablePointer<pthread_rwlock_t> = .allocate(capacity: 1)
        let status = pthread_rwlock_init(lock, nil)
        precondition(status == 0, "pthread_rwlock_init failed with status \(status)")
        return lock
    }

    @_documentation(visibility: internal)
    @inlinable
    @inline(__always)
    public func _pthreadWriteLock() { // swiftlint:disable:this identifier_name missing_docs
        let status = pthread_rwlock_wrlock(_rwLock)
        assert(status == 0, "pthread_rwlock_wrlock failed with status \(status)")
    }

    @_documentation(visibility: internal)
    @inlinable
    @inline(__always)
    public func _pthreadReadLock() { // swiftlint:disable:this identifier_name missing_docs
        let status = pthread_rwlock_rdlock(_rwLock)
        assert(status == 0, "pthread_rwlock_rdlock failed with status \(status)")
    }

    @_documentation(visibility: internal)
    @inlinable
    @inline(__always)
    public func _pthreadUnlock() { // swiftlint:disable:this identifier_name missing_docs
        let status = pthread_rwlock_unlock(_rwLock)
        assert(status == 0, "pthread_rwlock_unlock failed with status \(status)")
    }

    func pthreadDeinit() {
        let status = pthread_rwlock_destroy(_rwLock)
        assert(status == 0)
        _rwLock.deallocate()
    }
}


// MARK: Deprecations

extension _PThreadReadWriteLockProtocol {
    @_documentation(visibility: internal)
    @available(*, deprecated, renamed: "withReadLock(_:)") // swiftlint:disable:next missing_docs
    public func withReadLock<Result>(body: () throws -> Result) rethrows -> Result {
        try withReadLock(body)
    }
    
    @_documentation(visibility: internal)
    @available(*, deprecated, renamed: "withWriteLock(_:)") // swiftlint:disable:next missing_docs
    public func withWriteLock<Result>(body: () throws -> Result) rethrows -> Result {
        try withWriteLock(body)
    }
}
