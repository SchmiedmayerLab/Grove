//
// This source file is part of the Stanford RuntimeAssertions open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import RuntimeAssertions
import RuntimeAssertionsTesting
import Testing


@Suite("Runtime Assertions")
struct RuntimeAssertionsTests {
    @Test("Runtime Assertions")
    func testRuntimeAssertion() throws {
        struct RuntimeAssertionError: Error {}
        
        
        let messages = [
            "assertionFailure()",
            "assert(false)",
            "assert(42 == 42)"
        ]
        nonisolated(unsafe) var collectedMessages: [String] = []
        let number = 42

        expectRuntimeAssertion("\(#function)", expectedCount: 3) {
            assertionFailure(messages[0])
            assert(false, messages[1])
            assert(number != 42, messages[2])
        } assertion: { message in
            collectedMessages.append(message)
        }
        
        #expect(messages == collectedMessages)

        expectRuntimeAssertion {
            assertionFailure()
        } assertion: { message in
            #expect(message.isEmpty)
        }
        
        expectRuntimeAssertion {
            assertionFailure()
        }
        
        do {
            try expectRuntimeAssertion {
                assertionFailure()
                throw RuntimeAssertionError()
            }
        } catch is RuntimeAssertionError {
            return
        }
    }

    @Test("Async Runtime Assertion")
    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    func testAsyncRuntimeAssertion() async throws {
        try await confirmation { confirmation in
            try await expectRuntimeAssertion("\(#function)", expectedCount: 1) {
                try await Task.sleep(for: .seconds(0.02))
                assertionFailure("assertionFailure()")
                try await Task.sleep(for: .seconds(0.02))
            } assertion: { message in
                #expect(message == "assertionFailure()")
                confirmation()
            }
        }
    }

    @Test("Assertion not triggered")
    func testRuntimeAssertionNotTriggered() throws {
        struct RuntimeAssertionNotTriggeredError: Error {}
        withKnownIssue {
            let result = expectRuntimeAssertion {
                "Hello Paul 👋"
            }
            #expect(result == "Hello Paul 👋")
        }
        withKnownIssue {
            #expect(throws: RuntimeAssertionNotTriggeredError.self) {
                try expectRuntimeAssertion {
                    throw RuntimeAssertionNotTriggeredError()
                }
            }
        }
    }
    
    @Test("No assertions")
    func testNoAssertions() {
        expectRuntimeAssertion(expectedCount: 0) {
            // nothing
        }
    }

    @Test("Assertion without injection")
    func testCallHappensWithoutInjection() {
        #if DEBUG
        var called = false
        assert({
            called = true
            return true
        }(), "This could fail")
        #expect(called, "assert was never called!")
        #endif
    }

    @MainActor
    @Test("MainActor Annotated Closure")
    func testActorAnnotatedClosure() throws {
        @MainActor
        class Test {
            var property = "Hello World"

            nonisolated init() {}
        }

        let test = Test()

        expectRuntimeAssertion {
            assert(test.property != "Hello World", "Failed successfully")
        }
    }
}
