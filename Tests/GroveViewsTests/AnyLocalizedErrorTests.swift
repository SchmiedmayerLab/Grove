//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveViews
import Testing


@Suite
struct AnyLocalizedErrorTests {
    private enum TestError: Error {
        case abc
    }
    
    private class NSErrorSubclass: NSError, @unchecked Sendable {}
    
    
    private let domain = "org.grovealliance.GroveViews"
    
    @Test
    func fromNSErrorBasic() {
        let input = NSError(domain: domain, code: 0)
        let error = AnyLocalizedError(error: input)
        #expect(error.errorDescription == "The operation couldn’t be completed. (org.grovealliance.GroveViews error 0.)")
        #expect(error.failureReason == nil)
        #expect(error.helpAnchor == nil)
        #expect(error.recoverySuggestion == nil)
    }
    
    @Test
    func fromNSErrorExtended() {
        let input1 = NSError(domain: domain, code: 0, userInfo: [
            NSLocalizedDescriptionKey: "Localized Description Text",
            NSLocalizedFailureReasonErrorKey: "Localized Failure Reason Text",
            NSHelpAnchorErrorKey: "Help Anchor Text",
            NSLocalizedRecoverySuggestionErrorKey: "Localized Recovery Suggestion Text"
        ])
        let error1 = AnyLocalizedError(error: input1)
        #expect(error1.errorDescription == "Localized Description Text")
        #expect(error1.failureReason == "Localized Failure Reason Text")
        #expect(error1.helpAnchor == "Help Anchor Text")
        #expect(error1.recoverySuggestion == "Localized Recovery Suggestion Text")
        
        let input2 = NSErrorSubclass(domain: domain, code: 0, userInfo: [
            NSLocalizedDescriptionKey: "Localized Description Text",
            NSLocalizedFailureReasonErrorKey: "Localized Failure Reason Text",
            NSHelpAnchorErrorKey: "Help Anchor Text",
            NSLocalizedRecoverySuggestionErrorKey: "Localized Recovery Suggestion Text"
        ])
        let error2 = AnyLocalizedError(error: input2)
        #expect(error2.errorDescription == "Localized Description Text")
        #expect(error2.failureReason == "Localized Failure Reason Text")
        #expect(error2.helpAnchor == "Help Anchor Text")
        #expect(error2.recoverySuggestion == "Localized Recovery Suggestion Text")
    }
    
    @Test
    func isNSErrorChecking() {
        #expect(isNSError(NSError(domain: domain, code: 0)))
        #expect(isNSError(NSErrorSubclass(domain: domain, code: 0)))
        #expect(!isNSError(TestError.abc))
    }
}
