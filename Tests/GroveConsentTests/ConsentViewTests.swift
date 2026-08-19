//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)
import GroveConsent
import SnapshotTesting
import SwiftUI
import Testing


@Suite
@MainActor
struct ConsentViewTests {
    @Test
    func toggle() throws {
        let input = """
            Text1
            <toggle id=toggle1 initial-value=true expected-value=false>
            Can we contact you to tell you about future studies?
            </toggle>
            Text2
            """
        let doc = try ConsentDocument(markdown: input)
        let view = ConsentDocumentView(consentDocument: doc)
            .padding(.horizontal)
            .frame(width: 400, height: 200)
        assertSnapshot(of: view, as: .image)
    }
    
    @Test
    func toggleWithFootnote() throws {
        let input = """
            Text1
            <toggle id=toggle1 initial-value=true expected-value=false>
                Can we contact you to tell you about future studies?
                <footnote>You can change this later in Settings...</footnote>
            </toggle>
            Text2
            """
        let doc = try ConsentDocument(markdown: input)
        let view = ConsentDocumentView(consentDocument: doc)
            .padding(.horizontal)
            .frame(width: 400, height: 200)
        assertSnapshot(of: view, as: .image)
    }
    
    
    @Test
    func select() throws {
        let input = """
            Text1
            <select id=select1 initial-value=o1 expected-value="*">
                Please select your preferred option
                <option id=o1>ABC</>
                <option id=o2>DEF</>
            </select>
            Text2
            """
        let doc = try ConsentDocument(markdown: input)
        let view = ConsentDocumentView(consentDocument: doc)
            .padding(.horizontal)
            .frame(width: 400, height: 200)
        assertSnapshot(of: view, as: .image)
    }
    
    
    @Test
    func selectWithFootnote() throws {
        let input = """
            Text1
            <select id=select1 initial-value=o1 expected-value="*">
                Please select your preferred option
                <footnote>You can change this later in Settings...</footnote>
                <option id=o1>ABC</>
                <option id=o2>DEF</>
            </select>
            Text2
            """
        let doc = try ConsentDocument(markdown: input)
        let view = ConsentDocumentView(consentDocument: doc)
            .padding(.horizontal)
            .frame(width: 400, height: 200)
        assertSnapshot(of: view, as: .image)
    }
    
    
    @Test
    func selectWithFootnoteAndStyling() throws {
        let input = """
            Text1
            <select id=select1 initial-value=o1 expected-value="*">
                Please select your preferred option
                <footnote>
                If you select **yes**, the app will ...
                If you select **no**, the app will instead ...
                
                You can change this later in Settings...
                </footnote>
                <option id=o1>ABC</>
                <option id=o2>DEF</>
            </select>
            Text2
            """
        let doc = try ConsentDocument(markdown: input)
        let view = ConsentDocumentView(consentDocument: doc)
            .padding(.horizontal)
            .frame(width: 400, height: 200)
        assertSnapshot(of: view, as: .image)
    }
}
#endif
