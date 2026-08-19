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
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif


/// Covers what a message hands over when it is dragged, shared, or copied.
///
/// The invariant every test here defends is that ``ChatEntity/Content/canTransfer`` and the representations agree.
/// They did not: an image-only message reported itself transferable while the only representation was text, so it
/// handed over a zero-byte text file, and a message carrying a document offered plain text under the document's own
/// name — a file that opens as nonsense.
@Suite("Chat Content Transfer")
struct ChatContentTransferTests {
    private static func testImage() -> PlatformImage {
        #if canImport(UIKit)
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        #else
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()
        return image
        #endif
    }

    private static func testFile(named name: String = "labs.pdf") -> ChatEntity.Content.File {
        ChatEntity.Content.File(name: name, url: URL(fileURLWithPath: "/tmp/\(name)"), contentTypeIdentifier: "com.adobe.pdf")
    }

    @Test("Whatever reports itself transferable can actually be served")
    func canTransferAgreesWithTheRepresentations() {
        let cases: [ChatEntity.Content] = [
            .text("Just words."),
            .image(.image(Self.testImage())),
            .file(Self.testFile()),
            .init([.init(.image(.image(Self.testImage()))), .init(.text("Look at this."))]),
            // A remote image is the case that separates "has an image part" from "can produce one": nothing can
            // load it synchronously, so promising it would hand over an empty file.
            .image(.url(URL(string: "https://example.com/unreachable.png")!)),
            .init()
        ]

        for content in cases {
            // The three things `transferRepresentation` can produce, in the same order it declares them.
            let servesText = content.transferableText != nil
            let servesImage = content.images.first?.locallyLoadedImage != nil
            let servesFile = !content.files.isEmpty
            #expect(
                content.canTransfer == (servesText || servesImage || servesFile),
                "canTransfer must not promise something no representation can produce: \(content)"
            )
        }
    }

    @Test("An image-only message offers the image, not an empty text file")
    func imageOnlyContentOffersTheImage() {
        let content = ChatEntity.Content.image(.image(Self.testImage()))

        #expect(content.transferableText == nil, "there are no words, so the text representation has to refuse")
        #expect(content.images.first?.locallyLoadedImage?.pngData() != nil, "the image representation has to serve")
        #expect(content.canTransfer)
    }

    @Test("A document is never handed over as text under its own name")
    func fileContentDoesNotMasqueradeAsText() {
        let content = ChatEntity.Content.file(Self.testFile())

        #expect(content.transferableText == nil, "a file name is not the message's words")
        #expect(content.files.first?.name == "labs.pdf")
    }

    @Test("A caption travels with the attachment it was written for")
    func labelsBecomeTheText() {
        let content = ChatEntity.Content([
            .init(.image(.image(Self.testImage())), label: "The rash on day three"),
            .init(.file(Self.testFile()), label: "Bloodwork")
        ])

        #expect(content.transferableText == "The rash on day three\nBloodwork")
    }

    @Test("Copying names the attachments, since it always lands somewhere that takes text")
    func pasteboardTextNamesAttachments() {
        let withFile = ChatEntity.Content.file(Self.testFile())
        #expect(withFile.pasteboardText == "labs.pdf")

        let withText = ChatEntity.Content([.init(.text("See attached")), .init(.file(Self.testFile()))])
        #expect(withText.pasteboardText == "See attached\nlabs.pdf")

        #expect(ChatEntity.Content().pasteboardText == nil)
    }

    @Test("Every attached file can be handed over, not just the first")
    func eachFileIsTransferableOnItsOwn() {
        let files = [Self.testFile(named: "a.pdf"), Self.testFile(named: "b.pdf"), Self.testFile(named: "c.pdf")]
        let content = ChatEntity.Content(files.map { .init(.file($0)) })

        // `Content` describes one item in several forms, so it offers the first file; the collection is what a
        // caller shares to hand over all of them, which is why `File` is `Transferable` in its own right.
        #expect(content.files.count == 3)
        #expect(content.files.first?.name == "a.pdf")
        #expect(content.files.map(\.name) == ["a.pdf", "b.pdf", "c.pdf"])
    }

    @Test("An empty message offers nothing at all")
    func emptyContentIsNotTransferable() {
        let content = ChatEntity.Content()

        #expect(!content.canTransfer)
        #expect(content.transferableText == nil)
        #expect(content.pasteboardText == nil)
    }
}
