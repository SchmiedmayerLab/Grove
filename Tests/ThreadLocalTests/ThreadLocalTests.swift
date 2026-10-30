//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Synchronization
import Testing
import ThreadLocal


@Suite
struct ThreadLocalTests {
    /// A class instance that counts how many were made and released; each is numbered in the order it was made.
    private final class Tracked: Sendable {
        private static let counts = Mutex((made: 0, released: 0))

        static var released: Int {
            counts.withLock { $0.released }
        }

        let number: Int

        init() {
            number = Self.counts.withLock { counts in
                counts.made += 1
                return counts.made
            }
        }

        deinit {
            Self.counts.withLock { $0.released += 1 }
        }
    }

    /// The values `handle`'s deallocator received, in order.
    private static let deallocated = Mutex<[Int]>([])

    @ThreadLocal private static var var1: Int = 0
    @ThreadLocal private static var optional: Int?
    @ThreadLocal private static var optionalWithDefault: Int? = 5
    @ThreadLocal private static var tracked: Tracked = .init()
    @ThreadLocal(deallocator: .custom { value in ThreadLocalTests.deallocated.withLock { $0.append(value) } })
    private static var handle: Int = 1

    /// `body`'s result on a thread of its own, which starts with every thread-local unset; returns once `body` has.
    private static func onNewThread<Result: Sendable>(_ body: @escaping @Sendable () -> Result) -> Result {
        let result = Mutex<Result?>(nil)
        let done = DispatchSemaphore(value: 0)
        Thread {
            let value = body()
            result.withLock { $0 = value }
            done.signal()
        }.start()
        done.wait()
        guard let value = result.withLock({ $0 }) else {
            preconditionFailure("The thread signals only after it stored its result.")
        }
        return value
    }

    /// Waits until `condition` holds, for at most five seconds: a thread runs its thread-locals' cleanup as it exits,
    /// after its body returned.
    private static func eventually(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        return condition()
    }

    @Test
    func testSimpleInt() {
        let threads = (0..<10).map { threadIdx in
            let thread = Thread {
                var lastValue = 0
                while !Thread.current.isCancelled {
                    #expect(Self.var1 == lastValue, "threadIdx: \(threadIdx)")
                    let randInt = Int.random(in: .min...(.max))
                    Self.var1 = randInt
                    lastValue = Self.var1
                    #expect(lastValue == randInt, "threadIdx: \(threadIdx)")
                }
            }
            thread.name = "TT:\(threadIdx)"
            return thread
        }
        for thread in threads {
            thread.start()
        }
        sleep(5)
        for thread in threads {
            thread.cancel()
        }
        sleep(1)
    }

    @Test("An optional starts at its default, and a nil a thread sets stays nil instead of resetting to the default")
    func optionalValues() {
        let reads = Self.onNewThread {
            var reads: [Int?] = [Self.optional, Self.optionalWithDefault]
            Self.optional = 3
            reads.append(Self.optional)
            Self.optional = nil
            reads.append(Self.optional)
            Self.optionalWithDefault = nil
            reads.append(Self.optionalWithDefault)
            return reads
        }
        #expect(reads == [nil, 5, 3, nil, nil])
        #expect(Self.onNewThread { Self.optionalWithDefault } == 5, "another thread starts at the default")
    }

    @Test("A thread reads the same instance every time, another thread its own, and each thread's exit releases it")
    func classValuesArePerThread() {
        let releasedBefore = Tracked.released
        let first = Self.onNewThread { (Self.tracked.number, Self.tracked.number) }
        let second = Self.onNewThread { Self.tracked.number }
        #expect(first.0 == first.1)
        #expect(second != first.0)
        #expect(Self.eventually { Tracked.released >= releasedBefore + 2 })
    }

    @Test("The deallocator gets the value a write replaces and, when the thread exits, the value it ends with")
    func deallocatorGetsReplacedAndFinalValues() {
        let before = Self.deallocated.withLock { $0.count }
        Self.onNewThread {
            _ = Self.handle
            Self.handle = 2
        }
        #expect(Self.eventually { Self.deallocated.withLock { $0.count } >= before + 2 })
        #expect(Self.deallocated.withLock { Array($0[before...]) } == [1, 2])
    }
}
