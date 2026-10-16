//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveConsent
@testable import GroveFoundation
import Testing


@Suite
struct ConsentParserTests {
    @Test
    @MainActor
    func simpleParsing() throws {
        let input = """
            # Hello World
            
            This is our study.
            
            We look forward to welcoming you into the fold.
            - we
            - look
            - forward
            - to welcoming you
            """
        let document = try ConsentDocument(markdown: input)
        #expect(document.metadata.isEmpty)
        #expect(document.sections == [
            .markdown(input)
        ])
    }
    
    @Test
    @MainActor
    func frontmatterParsing() throws {
        let input = """
            ---
            title: abc
            version: 1.0.2
            keyOnlyEntry:
            keyAndValueEntry: value
            ---
            
            First markdown block
            - abc
            - def
            """
        let document = try ConsentDocument(markdown: input)
        #expect(document.metadata == [
            "title": "abc",
            "version": "1.0.2",
            "keyOnlyEntry": "",
            "keyAndValueEntry": "value"
        ])
        #expect(document.metadata.title == "abc")
        #expect(document.metadata.version == Version(1, 0, 2))
        #expect(document.sections == [
            .markdown("First markdown block\n- abc\n- def")
        ])
    }
    
    @Test
    @MainActor
    func customElementParsing() throws {
        let input = """
            Hello *there* :)
            <toggle id=toggle1 initial-value=true expected-value=false>Prompt1</toggle>
            <toggle id=toggle2 initial-value=false expected-value=true>Prompt2</>
            <toggle id=toggle3 expected-value=true>Prompt3</>
            some more markdown
            <select id=select1 initial-value=option1>
                Please select your preference
                <option id=option1>Option1</>
                <option id=option2>Option2</>
            </select>
            even more mark down
            <signature id=sig1></signature>
            """
        let document = try ConsentDocument(markdown: input)
        #expect(document.metadata.isEmpty)
        try #require(document.sections.count == 8)
        #expect(document.sections[0] == .markdown("Hello *there* :)"))
        #expect(document.sections[4] == .markdown("some more markdown"))
        #expect(document.sections[6] == .markdown("even more mark down"))
        #expect(document.sections[7] == .signature(.init(id: "sig1")))
        let toggles = document.sections.compactMap { section in
            if case .toggle(let toggle) = section { toggle } else { nil }
        }
        #expect(toggles.map(\.id) == ["toggle1", "toggle2", "toggle3"])
        #expect(toggles.map(\.initialValue) == [true, false, false])
        #expect(toggles.map(\.expectedValue) == [false, true, true])
        #expect(toggles.map(\.text.blocks) == [
            [.markdown(id: nil, rawContents: "Prompt1")],
            [.markdown(id: nil, rawContents: "Prompt2")],
            [.markdown(id: nil, rawContents: "Prompt3")]
        ])
        let selection = try #require(document.sections.compactMap { section in
            if case .select(let selection) = section { selection } else { nil }
        }.first)
        #expect(selection.id == "select1")
        #expect(selection.text.blocks == [.markdown(id: nil, rawContents: "Please select your preference")])
        #expect(selection.options.map(\.id) == ["option1", "option2"])
        #expect(selection.options.map(\.title) == ["Option1", "Option2"])
        #expect(selection.initialValue == "option1")
        #expect(selection.expectedSelection == .anything(allowEmptySelection: true))
    }
    
    @Test(arguments: [
        "<signature id=sig></signature>",
        "<signature id=sig></>",
        "<signature id=sig />"
    ])
    @MainActor
    func endOfTagHandling(input: String) throws {
        let document = try ConsentDocument(markdown: input)
        #expect(document.metadata.isEmpty)
        #expect(document.sections == [
            .signature(.init(id: "sig"))
        ])
    }
    
    @Test
    @MainActor
    func select0() throws {
        let input = """
            <select id=select1 initial-value=option1>
                <option id=option1>Text</>
            </select>
            """
        let document = try ConsentDocument(markdown: input)
        let selection = try singleSelection(in: document)
        #expect(selection.id == "select1")
        #expect(selection.text.blocks.isEmpty)
        #expect(selection.options.map(\.id) == ["option1"])
        #expect(selection.options.map(\.title) == ["Text"])
        #expect(selection.initialValue == "option1")
        #expect(selection.expectedSelection == .anything(allowEmptySelection: true))
    }
    
    @Test
    @MainActor
    func select1() throws {
        let input = """
            <select id=select1 expected-value="*">
                Please select
                <option id=o1>T1</>
                your preferred option
                <option id=o2>T2</>
            </select>
            """
        let document = try ConsentDocument(markdown: input)
        let selection = try singleSelection(in: document)
        #expect(selection.id == "select1")
        #expect(selection.text.blocks == [
            .markdown(id: nil, rawContents: "Please select"),
            .markdown(id: nil, rawContents: "your preferred option")
        ])
        #expect(selection.options.map(\.id) == ["o1", "o2"])
        #expect(selection.options.map(\.title) == ["T1", "T2"])
        #expect(selection.initialValue.isEmpty)
        #expect(selection.expectedSelection == .anything(allowEmptySelection: false))
    }
    
    @Test
    @MainActor
    func select2() throws {
        let input = """
            <select id=select1 expected-value="*">
                Please select your preferred option
                <footnote>You can change this later in Settings...</footnote>
                <option id=o1>T1</>
                <option id=o2>T2</>
            </select>
            """
        let document = try ConsentDocument(markdown: input)
        let selection = try singleSelection(in: document)
        #expect(selection.id == "select1")
        #expect(selection.text.blocks == [
            .markdown(id: nil, rawContents: "Please select your preferred option"),
            .customElement(.init(
                name: "footnote",
                attributes: [],
                content: [.text("You can change this later in Settings...")],
                raw: "<footnote>You can change this later in Settings...</footnote>"
            ))
        ])
        #expect(selection.options.map(\.id) == ["o1", "o2"])
        #expect(selection.options.map(\.title) == ["T1", "T2"])
        #expect(selection.initialValue.isEmpty)
        #expect(selection.expectedSelection == .anything(allowEmptySelection: false))
    }
    
    @Test
    @MainActor
    func invalidInput0() throws {
        let input = """
            <select id=select1 initial-value=o3>
                <option id=o1>T1</>
                <option id=o2>T2</>
            </select>
            """
        #expect(throws: (any Error).self) {
            try ConsentDocument(markdown: input)
        }
    }
    
    @Test
    @MainActor
    func invalidInput1() throws {
        let input = """
            <select id=select1 expected-value=o3>
                <option id=o1>T1</>
                <option id=o2>T2</>
            </select>
            """
        #expect(throws: (any Error).self) {
            try ConsentDocument(markdown: input)
        }
    }

    private func singleSelection(in document: ConsentDocument) throws -> ConsentDocument.SelectConfig {
        try #require(document.sections.count == 1)
        return try #require(document.sections.compactMap { section in
            if case .select(let selection) = section { selection } else { nil }
        }.first)
    }
}
