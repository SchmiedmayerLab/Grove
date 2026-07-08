//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziFoundation
import XCTest


final class RWLockTests: XCTestCase {
    func testConcurrentReads() {
        let lock = RWLock()
        let expectation1 = self.expectation(description: "First read")
        let expectation2 = self.expectation(description: "Second read")

        Task.detached {
            lock.withReadLock {
                usleep(100_000) // Simulate read delay (200ms)
                expectation1.fulfill()
            }
        }

        Task.detached {
            lock.withReadLock {
                usleep(100_000) // Simulate read delay (200ms)
                expectation2.fulfill()
            }
        }

        wait(for: [expectation1, expectation2], timeout: 1.0)
    }

    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    func testWriteBlocksOtherWrites() {
        let lock = RWLock()
        let expectation1 = self.expectation(description: "First write")
        let expectation2 = self.expectation(description: "Second write")

        Task.detached {
            lock.withWriteLock {
                usleep(200_000) // Simulate write delay (200ms)
                expectation1.fulfill()
            }
        }

        Task.detached {
            try await Task.sleep(for: .milliseconds(100))
            lock.withWriteLock {
                expectation2.fulfill()
            }
        }

        wait(for: [expectation1, expectation2], timeout: 1.0)
    }

    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    func testWriteBlocksReads() {
        let lock = RWLock()
        let expectation1 = self.expectation(description: "Write")
        let expectation2 = self.expectation(description: "Read")

        Task.detached {
            lock.withWriteLock {
                usleep(200_000) // Simulate write delay (200ms)
                expectation1.fulfill()
            }
        }

        Task.detached {
            try await Task.sleep(for: .milliseconds(100))
            lock.withReadLock {
                expectation2.fulfill()
            }
        }

        wait(for: [expectation1, expectation2], timeout: 1.0)
    }

    // This test is temporarily disabled on Linux.
    //
    // Reason: `lock.isWriteLocked()` behaves differently between Glibc (Linux) and macOS.
    // On macOS, `pthread_rwlock_trywrlock()` returns `EDEADLK` when the calling thread
    // already owns the lock, which makes `isWriteLocked()` work as expected.
    //
    // On Linux (glibc), `pthread_rwlock_trywrlock()` instead returns `EBUSY` in the same
    // scenario (only `pthread_rwlock_wrlock()` can return `EDEADLK`)
    //
    // To make this portable, `RWLock` would need to explicitly track ownership
    // of the lock by the current thread.
    //
    // See
    // - https://linux.die.net/man/3/pthread_rwlock_trywrlock
    // - https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/pthread_rwlock_trywrlock.3.html
    func testIsWriteLocked() {
#if canImport(Darwin)
        let lock = RWLock()

        Task.detached {
            lock.withWriteLock {
                XCTAssertTrue(lock.isWriteLocked())
                usleep(100_000) // Simulate write delay (100ms)
            }
        }

        usleep(50_000) // Give the other thread time to lock (50ms)
        XCTAssertFalse(lock.isWriteLocked())
#endif
    }


    func testMultipleLocksAcquired() {
        let lock1 = RWLock()
        let lock2 = RWLock()
        let expectation1 = self.expectation(description: "Read")

        Task.detached {
            lock1.withReadLock {
                lock2.withReadLock {
                    expectation1.fulfill()
                }
            }
        }

        wait(for: [expectation1], timeout: 1.0)
    }


    func testConcurrentReadsRecursive() {
        let lock = RecursiveRWLock()
        let expectation1 = self.expectation(description: "First read")
        let expectation2 = self.expectation(description: "Second read")

        Task.detached {
            lock.withReadLock {
                usleep(100_000) // Simulate read delay 100 ms
                expectation1.fulfill()
            }
        }

        Task.detached {
            lock.withReadLock {
                usleep(100_000) // Simulate read delay 100ms
                expectation2.fulfill()
            }
        }

        wait(for: [expectation1, expectation2], timeout: 1.0)
    }

    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    func testWriteBlocksOtherWritesRecursive() {
        let lock = RecursiveRWLock()
        let expectation1 = self.expectation(description: "First write")
        let expectation2 = self.expectation(description: "Second write")

        Task.detached {
            lock.withWriteLock {
                usleep(200_000) // Simulate write delay 200ms
                expectation1.fulfill()
            }
        }

        Task.detached {
            try await Task.sleep(for: .milliseconds(100))
            lock.withWriteLock {
                expectation2.fulfill()
            }
        }

        wait(for: [expectation1, expectation2], timeout: 1.0)
    }

    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    func testWriteBlocksReadsRecursive() {
        let lock = RecursiveRWLock()
        let expectation1 = self.expectation(description: "Write")
        let expectation2 = self.expectation(description: "Read")

        Task.detached {
            lock.withWriteLock {
                usleep(200_000) // Simulate write delay 200 ms
                expectation1.fulfill()
            }
        }

        Task.detached {
            try await Task.sleep(for: .milliseconds(100))
            lock.withReadLock {
                expectation2.fulfill()
            }
        }

        wait(for: [expectation1, expectation2], timeout: 1.0)
    }

    func testMultipleLocksAcquiredRecursive() {
        let lock1 = RecursiveRWLock()
        let lock2 = RecursiveRWLock()
        let expectation1 = self.expectation(description: "Read")

        Task.detached {
            lock1.withReadLock {
                lock2.withReadLock {
                    expectation1.fulfill()
                }
            }
        }

        wait(for: [expectation1], timeout: 1.0)
    }

    func testRecursiveReadReadAcquisition() {
        let lock = RecursiveRWLock()
        let expectation1 = self.expectation(description: "Read")

        Task.detached {
            lock.withReadLock {
                lock.withReadLock {
                    expectation1.fulfill()
                }
            }
        }

        wait(for: [expectation1], timeout: 1.0)
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *)
    func testRecursiveWriteRecursiveAcquisition() {
        let lock = RecursiveRWLock()
        let expectation1 = self.expectation(description: "Read")
        let expectation2 = self.expectation(description: "ReadWrite")
        let expectation3 = self.expectation(description: "WriteRead")
        let expectation4 = self.expectation(description: "Write")

        let expectation5 = self.expectation(description: "Race")

        Task.detached {
            lock.withWriteLock {
                usleep(50_000) // Simulate write delay 50 ms
                lock.withReadLock {
                    expectation1.fulfill()
                    usleep(200_000) // Simulate write delay 200 ms
                    lock.withWriteLock {
                        expectation2.fulfill()
                    }
                }

                lock.withWriteLock {
                    usleep(200_000) // Simulate write delay 200 ms
                    lock.withReadLock {
                        expectation3.fulfill()
                    }
                    expectation4.fulfill()
                }
            }
        }

        Task.detached {
            await withDiscardingTaskGroup { group in
                for _ in 0..<10 {
                    group.addTask {
                        // random sleep up to 50 ms
                        try? await Task.sleep(nanoseconds: UInt64.random(in: 0...50_000_000))
                        lock.withWriteLock {
                            _ = usleep(100)
                        }
                    }
                }
            }

            expectation5.fulfill()
        }

        wait(for: [expectation1, expectation2, expectation3, expectation4, expectation5], timeout: 20.0)
    }
}
