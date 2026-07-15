//
// This source file is part of the Stanford RuntimeAssertions open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import func Foundation.NSClassFromString


/// Execute a block of code only in debug or testing builds.
/// - Parameters:
///   - block: The block to execute in debug or testing builds.
///   - else: The block to execute in release or non-testing builds.
@inlinable
@inline(always)
func debugOnly(_ block: () -> Void, else: () -> Void = {}) {
    // we abuse the power of assert to optimize out our call to `block`
    var called = false
    Swift.assert({
        block()
        called = true
        return true
    }())
    guard !called else {
        return
    }
    let isRunningInXCTest = NSClassFromString("XCTestCase") != nil
    if isRunningInXCTest {
        block()
    } else {
        `else`()
    }
}
