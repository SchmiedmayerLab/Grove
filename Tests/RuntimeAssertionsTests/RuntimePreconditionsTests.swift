//
// This source file is part of the Grove open-source project
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
    @available(*, deprecated, message: "Covers the deprecated runtime precondition expectations.")
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
    @available(*, deprecated, message: "Covers the deprecated runtime precondition expectations.")
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
    @available(*, deprecated, message: "Covers the deprecated runtime precondition expectations.")
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
    @available(*, deprecated, message: "Covers the deprecated runtime precondition expectations.")
    func testNoPrecondition() {
        expectNoRuntimePrecondition {
            // nothing
        }
    }
    
    @Test("No preconditions")
    @available(*, deprecated, message: "Covers the deprecated runtime precondition expectations.")
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
}
