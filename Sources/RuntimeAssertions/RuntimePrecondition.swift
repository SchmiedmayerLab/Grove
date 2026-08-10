//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

package import Foundation
private struct UnsafeSendable<Value>: @unchecked Sendable {
    let value: Value
}


package func withRuntimePrecondition(
    timeout: TimeInterval,
    validatePrecondition: (@Sendable (String) -> Void)?,
    _ expression: @escaping () -> Void,
    validate: (Int) -> Void
) {
    let counter = Counter()
    let injection = createInjection(fulfillmentCount: counter, validate: validatePrecondition)

    defer {
        validate(counter.count)
    }

    // We have to run the operation on a `DispatchQueue` as we have to call `RunLoop.current.run()` in the `preconditionFailure` call.
    let dispatchQueue = DispatchQueue(label: "RuntimePrecondition-\(injection.id)")

    let expressionWorkItem = DispatchWorkItem {
        injection.withInjection(expression)
    }
    dispatchQueue.async(execute: expressionWorkItem)

    // We don't use:
    // `wait(for: [expectation], timeout: timeout)`
    // here as we need to make the method independent of XCTestCase to also use it in our TestApp UITest target which fails if you import XCTest.
    usleep(useconds_t(1_000_000 * timeout))
    expressionWorkItem.cancel()
}


package func withRuntimePrecondition(
    timeout: TimeInterval,
    validatePrecondition: (@Sendable (String) -> Void)?,
    _ expression: @escaping () async -> Void,
    validate: (Int) -> Void
) {
    let counter = Counter()
    let injection = createInjection(fulfillmentCount: counter, validate: validatePrecondition)

    defer {
        validate(counter.count)
    }

    let expressionClosure = UnsafeSendable(value: expression)
    let task = Task {
        await injection.withInjection(expressionClosure.value)
    }

    // We don't use:
    // `wait(for: [expectation], timeout: timeout)`
    // here as we need to make the method independent of XCTestCase to also use it in our TestApp UITest target which fails if you import XCTest.
    usleep(useconds_t(1_000_000 * timeout))
    task.cancel()
}


private func createInjection(fulfillmentCount: Counter, validate: (@Sendable (String) -> Void)?) -> RuntimeAssertionInjection {
    RuntimeAssertionInjection(precondition: { condition, message, _, _  in
        if !condition() {
            let message = message()
            validate?(message)
            fulfillmentCount.increment()
            neverReturn()
        }
    })
}
