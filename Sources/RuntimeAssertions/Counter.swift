//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


package final class Counter: Sendable {
    nonisolated(unsafe) private var counter: Int
    private let lock = NSLock()

    package var count: Int {
        lock.withLock {
            counter
        }
    }

    
    package init(counter: Int = 0) {
        self.counter = counter
    }

    package func increment() {
        lock.withLock {
            counter += 1
        }
    }
}
