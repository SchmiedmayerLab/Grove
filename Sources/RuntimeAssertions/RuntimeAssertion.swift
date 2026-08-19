//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


package func withRuntimeAssertion<T, E: Error>(
    validateAssertion: (@Sendable (String) -> Void)?,
    _ expression: () throws(E) -> T,
    validate: (Int) -> Void
) throws(E) -> T {
    let counter = Counter()
    let injection = createInjection(fulfillmentCount: counter, validate: validateAssertion)

    defer {
        validate(counter.count)
    }

    return try injection.withInjection(expression)
}


package func withRuntimeAssertion<T, E: Error>(
    validateAssertion: (@Sendable (String) -> Void)?,
    _ expression: () async throws(E) -> T,
    validate: (Int) -> Void
) async throws(E) -> T {
    let counter = Counter()
    let injection = createInjection(fulfillmentCount: counter, validate: validateAssertion)

    defer {
        validate(counter.count)
    }

    return try await injection.withInjection(expression)
}


private func createInjection(fulfillmentCount: Counter, validate: (@Sendable (String) -> Void)?) -> RuntimeAssertionInjection {
    RuntimeAssertionInjection(assert: { condition, message, _, _  in
        if !condition() {
            let message = message()
            validate?(message)
            fulfillmentCount.increment()
        }
    })
}
