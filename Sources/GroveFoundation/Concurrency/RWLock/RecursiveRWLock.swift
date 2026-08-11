//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Atomics
public import Foundation


/// Recursive Read-Write Lock using `pthread_rwlock`.
///
/// This is a recursive version of the ``RWLock`` implementation.
public final class RecursiveRWLock: _PThreadReadWriteLockProtocol, @unchecked Sendable {
    public let _rwLock: UnsafeMutablePointer<pthread_rwlock_t> // swiftlint:disable:this identifier_name

    private let writerThread = AtomicPThread(nil)
    private var writerCount = 0
    private var readerCount = 0

    /// Create a new recursive read-write lock.
    public init() {
        _rwLock = Self.pthreadInit()
    }
    
    
    // MARK: Operations
    
    @inlinable
    @inline(__always)
    public func withReadLock<Result, E>(_ body: () throws(E) -> Result) throws(E) -> Result {
        _readLock()
        defer {
            _readUnlock()
        }
        return try body()
    }

    @inlinable
    @inline(__always)
    public func withWriteLock<Result, E>(_ body: () throws(E) -> Result) throws(E) -> Result {
        _writeLock()
        defer {
            _writeUnlock()
        }
        return try body()
    }
    
    @usableFromInline
    func _readLock() { // swiftlint:disable:this identifier_name
        let selfThread = pthread_self()
        if let writer = writerThread.load(ordering: .relaxed),
           pthread_equal(writer, selfThread) != 0 {
            // we know that the writerThread is us, so access to `readerCount` is synchronized (its us that holds the rwLock).
            readerCount += 1
            assert(readerCount > 0, "Synchronization issue. Reader count is unexpectedly low: \(readerCount)")
            return
        }
        _pthreadReadLock()
    }

    
    // MARK: Implementation
    
    @usableFromInline
    func _readUnlock() { // swiftlint:disable:this identifier_name
        // we assume this is called while holding the reader lock, so access to `readerCount` is safe
        if readerCount > 0 {
            // fine to go down to zero (we still hold the lock in write mode)
            readerCount -= 1
            return
        }
        _pthreadUnlock()
    }
    

    @usableFromInline
    func _writeLock() { // swiftlint:disable:this identifier_name
        let selfThread = pthread_self()
        if let writer = writerThread.load(ordering: .relaxed),
           pthread_equal(writer, selfThread) != 0 {
            // we know that the writerThread is us, so access to `writerCount` is synchronized (its us that holds the rwLock).
            writerCount += 1
            assert(writerCount > 1, "Synchronization issue. Writer count is unexpectedly low: \(writerCount)")
            return
        }
        _pthreadWriteLock()
        writerThread.store(selfThread, ordering: .relaxed)
        writerCount = 1
    }

    @usableFromInline
    func _writeUnlock() { // swiftlint:disable:this identifier_name
        // we assume this is called while holding the write lock, so access to `writerCount` is safe
        if writerCount > 1 {
            writerCount -= 1
            return
        }
        // otherwise it is the last unlock
        writerThread.store(nil, ordering: .relaxed)
        writerCount = 0
        _pthreadUnlock()
    }

    deinit {
        pthreadDeinit()
    }
}
