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
    #if compiler(>=6.4)
    @diagnose(DeprecatedDeclaration, as: ignored, reason: "Covers the deprecated runtime precondition expectations.")
    #endif
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
    #if compiler(>=6.4)
    @diagnose(DeprecatedDeclaration, as: ignored, reason: "Covers the deprecated runtime precondition expectations.")
    #endif
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
    #if compiler(>=6.4)
    @diagnose(DeprecatedDeclaration, as: ignored, reason: "Covers the deprecated runtime precondition expectations.")
    #endif
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
    #if compiler(>=6.4)
    @diagnose(DeprecatedDeclaration, as: ignored, reason: "Covers the deprecated runtime precondition expectations.")
    #endif
    func testNoPrecondition() {
        expectNoRuntimePrecondition {
            // nothing
        }
    }
    
    @Test("No preconditions")
    #if compiler(>=6.4)
    @diagnose(DeprecatedDeclaration, as: ignored, reason: "Covers the deprecated runtime precondition expectations.")
    #endif
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
