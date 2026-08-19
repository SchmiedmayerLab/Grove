//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveChat
@testable import GroveLLM
@testable import GroveLLMOpenAI
import Testing
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif


/// Covers the boundary where a message the user composed becomes something the model is actually sent.
///
/// A message is an ordered list of parts, and a part kind that the bridge does not know about is dropped in
/// silence: it still renders in the chat, so nothing looks wrong, and the model simply never sees it. Files
/// shipped that way once already. ``everyPartKindSurvivesTheWriteBack`` is written so that the next kind added to
/// ``ChatEntity/Content/PartKind`` cannot repeat it — the switch there has no `default`, so a new case stops
/// compiling until this suite says what reaching the model means for it.
@Suite("LLM Context Attachments")
@MainActor
struct LLMContextAttachmentTests {
    /// A file on disk, since an attachment is only ever a reference to one.
    private static func makeFile(named name: String = "notes.txt", contents: String = "Attach me.") throws -> ChatEntity.Content.File {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString)-\(name)")
        try Data(contents.utf8).write(to: url)
        return ChatEntity.Content.File(name: name, url: url, contentTypeIdentifier: "public.plain-text")
    }

    private static func makeImage() -> LLMContextEntity._PlatformImage {
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

    @Test("Every kind of part a message can carry reaches the context")
    func everyPartKindSurvivesTheWriteBack() throws {
        let everyKind: [ChatEntity.Content.PartKind] = [
            .text("Read this."),
            .image(.image(Self.makeImage())),
            .file(try Self.makeFile())
        ]

        for kind in everyKind {
            var context = LLMContext()
            var chat = context.chat
            chat.append(ChatEntity(role: .user, content: .init([.init(kind)])))
            context.chat = chat

            // No `default`: a new part kind has to be answered for here before it can ship.
            switch kind {
            case .text(let text):
                #expect(context.contains { $0.content == text }, "text has to reach the context")
            case .image:
                #expect(context.contains { $0._imageContent != nil }, "an image has to reach the context")
            case .file:
                #expect(context.contains { $0._fileContent != nil }, "a file has to reach the context")
            }
        }
    }

    @Test("An attached file lands in the context as an inline payload")
    func fileWriteBack() throws {
        let file = try Self.makeFile()
        var context = LLMContext()
        var chat = context.chat
        let entity = ChatEntity(role: .user, content: .init([.init(.file(file)), .init(.text("Summarise this."))]))
        chat.append(entity)
        context.chat = chat

        #expect(context.count == 2)
        let fileContent = try #require(context[0]._fileContent, "the file must be carried, not dropped")
        #expect(fileContent.filename == "notes.txt")
        #expect(fileContent.contentType == "text/plain", "the wire wants a MIME type, not a UTI")
        #expect(Data(base64Encoded: fileContent.base64Data) == Data("Attach me.".utf8))
        #expect(context[1].content == "Summarise this.")
        #expect(context[1].id == entity.id, "the text entity carries the chat entity's identity")

        context.chat = chat
        #expect(context.count == 2, "the write-back stays idempotent")
    }

    @Test("A file-only message carries the chat entity's identity on its last attachment")
    func fileOnlyWriteBackIsIdempotent() throws {
        var context = LLMContext()
        var chat = context.chat
        let entity = ChatEntity(role: .user, content: .init([
            .init(.file(try Self.makeFile(named: "a.txt"))),
            .init(.file(try Self.makeFile(named: "b.txt")))
        ]))
        chat.append(entity)
        context.chat = chat

        #expect(context.count == 2)
        #expect(context.last?.id == entity.id)

        context.chat = chat
        #expect(context.count == 2, "without a text entity the identity still has to pin the write-back")
    }

    @Test("An attached file surfaces in the chat again")
    func fileProjection() throws {
        let file = try Self.makeFile()
        var context = LLMContext()
        context.append(
            try #require(LLMContextEntity(_role: .user, fileURL: file.url, contentType: "text/plain", filename: file.name))
        )

        let chatEntity = try #require(context.chat.first)
        let projected = try #require(chatEntity.content.files.first, "a file entity must project back as a file part")
        #expect(projected.name == "notes.txt", "the user's name for the file survives the round trip")
        #expect(projected.url == file.url)
    }

    @Test("A file the model is sent travels as an input_file item")
    func fileReachesTheWire() throws {
        let file = try Self.makeFile()
        let entity = try #require(
            LLMContextEntity(_role: .user, fileURL: file.url, contentType: "text/plain", filename: file.name)
        )

        let items = entity.toResponsesInputItems()
        #expect(items.count == 1)
        guard case .Item(.InputMessage(let message)) = try #require(items.first),
              case .InputFileContent(let sent) = try #require(message.content.first) else {
            Issue.record("Expected the file to be sent as an input_file item, got \(items)")
            return
        }
        #expect(sent._type == .input_file)
        #expect(sent.filename == "notes.txt")
        #expect(sent.file_data?.hasPrefix("data:text/plain;base64,") == true, "the payload has to be a data URL")
    }

    @Test("Chat Completions rejects files instead of silently sending an empty message")
    func chatCompletionsRejectsFiles() throws {
        let file = try Self.makeFile()
        let context = LLMContext([
            try #require(LLMContextEntity(_role: .user, fileURL: file.url, contentType: "text/plain"))
        ])

        #expect(chatCompletionsCompatibilityError(in: context) == .fileAttachmentsRequireResponsesAPI)
    }

    @Test("An image the model is sent still travels as an input_image item")
    func imageReachesTheWire() throws {
        let entity = try #require(
            LLMContextEntity(_role: .user, image: Self.makeImage(), format: .jpeg(compressionFactor: 0.8))
        )

        let items = entity.toResponsesInputItems()
        guard case .Item(.InputMessage(let message)) = try #require(items.first),
              case .InputImageContent(let sent) = try #require(message.content.first) else {
            Issue.record("Expected the image to be sent as an input_image item, got \(items)")
            return
        }
        #expect(sent.image_url?.hasPrefix("data:image/jpeg;base64,") == true)
    }
}
