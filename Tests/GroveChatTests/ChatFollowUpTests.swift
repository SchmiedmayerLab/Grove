//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import GroveChat
import Testing


@Suite("Chat Follow-Up")
struct ChatFollowUpTests {
    @Test("A quotation becomes a block quote, one marker per line")
    func quotesEveryLine() {
        #expect("received".markdownQuoted == "> received")
        #expect("first\nsecond".markdownQuoted == "> first\n> second")
    }

    @Test("The quotation leads and the question follows, a blank line apart")
    func quotationThenQuestion() {
        let message = String.message(quoting: "received", text: "What does this mean?")

        #expect(message == "> received\n\nWhat does this mean?")
    }

    @Test("A quotation on its own is a message; so is a question on its own")
    func eitherPartAlone() {
        #expect(String.message(quoting: "received", text: "") == "> received")
        #expect(String.message(quoting: nil, text: "What does this mean?") == "What does this mean?")
    }

    @Test("Blank text is never staged as a quotation")
    func ignoresBlankText() {
        let followUp = ChatFollowUp()

        followUp.quote("   \n  ")

        #expect(followUp.pendingQuotation == nil)
    }

    @Test("A quotation is trimmed before it is staged")
    func trimsBeforeStaging() {
        let followUp = ChatFollowUp()

        followUp.quote("  received.  \n")

        #expect(followUp.pendingQuotation == "received.")
    }
}
