//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveChat
import Testing


/// Covers the content model a message is built from.
@Suite("Chat Content")
struct ChatContentTests {
    @Test("Adjacent text is one part, so a streamed answer never arrives as fragments")
    func adjacentTextMerges() {
        var content = ChatEntity.Content.text("Hel")
        content.append(.init(.text("lo")))
        content.append(.init(.text(" there")))

        #expect(content.parts.count == 1)
        #expect(content.text == "Hello there")
    }

    @Test("An attachment between text keeps the parts apart")
    func attachmentsSeparateText() {
        var content = ChatEntity.Content.text("before")
        content.append(.init(.file(.init(name: "notes.pdf", url: URL(fileURLWithPath: "/tmp/notes.pdf")))))
        content.append(.init(.text("after")))

        #expect(content.parts.count == 3)
        #expect(content.text == "beforeafter", "text reads as one run even when a part sits between")
        #expect(content.files.count == 1)
    }

    @Test("Order is kept, so what the model sent is what is shown")
    func partsKeepTheirOrder() {
        let file = ChatEntity.Content.File(name: "a.pdf", url: URL(fileURLWithPath: "/tmp/a.pdf"))
        let content = ChatEntity.Content([
            .init(.text("one")),
            .init(.file(file)),
            .init(.text("two"))
        ])

        #expect(content.count == 3, "Content iterates its parts directly")
        guard case .text = content[0].content, case .file = content[1].content else {
            Issue.record("Parts came back in a different order than they went in")
            return
        }
    }

    @Test("The convenience accessors agree with the parts")
    func accessorsMatchParts() {
        let content = ChatEntity.Content.images([.url(URL(string: "https://grove.stanford.edu/a.png")!)], text: "caption")

        #expect(content.images.count == 1)
        #expect(content.text == "caption")
        #expect(content.files.isEmpty)
        #expect(content.hasAttachments)
        #expect(!content.isEmpty)
    }

    @Test("Empty text is not content")
    func emptyTextIsEmpty() {
        #expect(ChatEntity.Content.text("").isEmpty)
        #expect(ChatEntity.Content().isEmpty)
        #expect(ChatEntity.Content.text("").text == nil, "an empty run reads as no text at all")
    }

    @Test("Content round-trips through Codable with its parts and their identity intact")
    func contentRoundTrips() throws {
        let file = ChatEntity.Content.File(
            name: "report.pdf",
            url: URL(fileURLWithPath: "/tmp/report.pdf"),
            contentTypeIdentifier: "com.adobe.pdf"
        )
        let original = ChatEntity.Content([
            .init(.text("see attached")),
            .init(.file(file), label: "The quarterly report")
        ])

        let decoded = try JSONDecoder().decode(
            ChatEntity.Content.self,
            from: try JSONEncoder().encode(original)
        )

        #expect(decoded == original)
        #expect(decoded.parts.map(\.id) == original.parts.map(\.id), "identity has to survive, or SwiftUI re-renders")
        #expect(decoded.parts.last?.label == "The quarterly report")
    }

    @Test("Content with no parts fails to decode")
    func emptyContentFailsToDecode() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ChatEntity.Content.self, from: Data(#"{"parts":[]}"#.utf8))
        }
    }

    @Test("A part carrying nothing recognisable fails to decode")
    func unknownPartFailsToDecode() {
        let json = #"{"parts":[{"id":"\#(UUID().uuidString)"}]}"#
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ChatEntity.Content.self, from: Data(json.utf8))
        }
    }

    @Test("Copying a file-only message names the file, while transferring it hands over the file itself")
    func attachmentsCopyAsTheirName() {
        let file = ChatEntity.Content.File(name: "scan.pdf", url: URL(fileURLWithPath: "/tmp/scan.pdf"))
        let content = ChatEntity.Content([.init(.file(file))])

        #expect(content.canTransfer)
        #expect(content.pasteboardText == "scan.pdf", "a file-only message still has something worth copying")
        #expect(content.transferableText == nil, "the file travels as itself, not as text wearing its name")
    }
}
