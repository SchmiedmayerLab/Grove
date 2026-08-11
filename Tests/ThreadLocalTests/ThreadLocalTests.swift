//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Testing
import ThreadLocal


@Suite
struct ThreadLocalTests {
    @ThreadLocal private static var var1: Int = 0

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
}
