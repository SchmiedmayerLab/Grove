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


@Suite("Runtime Precondition")
struct RuntimePreconditionsTests {
    @Test("Runtime Precondition")
    func testRuntimePrecondition() async {
        let number = 42

        await confirmation { confirmation in
            expectRuntimePrecondition(#function) {
                precondition(number != 42, "preconditionFailure()")
            } precondition: { message in
                #expect(message == "preconditionFailure()")
                confirmation()
            }
        }
        
        expectRuntimePrecondition {
            preconditionFailure()
        } precondition: { message in
            #expect(message.isEmpty)
        }
        
        expectRuntimePrecondition {
            preconditionFailure()
        }
    }

    @Test("Async Runtime Precondition")
    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    func testAsyncRuntimePrecondition() async {
        await confirmation { confirmation in
            expectRuntimePrecondition(timeout: 1.0) {
                try? await Task.sleep(for: .seconds(0.02))
                preconditionFailure("preconditionFailure()")
            } precondition: { message in
                #expect(message == "preconditionFailure()")
                confirmation()
            }
        }
    }

    @Test("Precondition not triggered")
    func testRuntimePreconditionNotTriggered() {
        withKnownIssue {
            expectRuntimePrecondition {
                print("Hello Paul 👋")
            }
        }

        withKnownIssue {
            expectRuntimePrecondition {
                Task {
                    preconditionFailure()
                }
                preconditionFailure()
            }
        }
    }
    
    @Test("No preconditions")
    func testNoPrecondition() {
        expectNoRuntimePrecondition {
            // nothing
        }
    }
    
    @Test("No preconditions")
    func testNoPreconditionAsync() {
        expectNoRuntimePrecondition { () async in
            // nothing
        }
    }

    @Test("Precondition without injection")
    func testCallHappensWithoutInjection() {
        var called = false

        precondition({
            called = true
            return true
        }(), "This could fail")

        #expect(called, "precondition was never called!")
    }

    @MainActor
    @Test("MainActor Annotated Closure")
    func testAsyncInvocationOnMainActor() {
        @MainActor
        class Test {
            var property = "Hello World"
        }

        let test = Test()

        expectRuntimePrecondition {
            precondition(test.property != "Hello World", "Failed successfully.")
        }
    }
}
