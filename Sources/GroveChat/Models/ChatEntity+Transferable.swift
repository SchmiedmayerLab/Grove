//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers


@available(iOS 18, macOS 15, watchOS 11, *)
extension ChatEntity.Content: Transferable {
    /// What went wrong offering content to the system.
    enum TransferError: Error {
        /// The content carries nothing of the requested kind.
        case nothingToTransfer
    }

    /// Offers a message's content to the rest of the system.
    ///
    /// A message is offered as each of the things it actually holds: its text, its first image, and its first
    /// attached file. Each is refused rather than faked when the message has none of that kind, so asking for an
    /// image never yields an empty text file.
    ///
    /// - Note: A `Transferable` value describes one item in several forms, so this offers the *first* image and the
    ///     *first* file. Offer ``ChatEntity/Content/files`` or ``ChatEntity/Content/images`` directly — both element
    ///     types are themselves `Transferable` — to hand over every attachment, as in
    ///     `ShareLink(items: message.content.files)`.
    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .utf8PlainText) { content in
            guard let text = content.transferableText else {
                throw TransferError.nothingToTransfer
            }
            return Data(text.utf8)
        }
        .suggestedFileName("Message.txt")

        DataRepresentation(exportedContentType: .png) { content in
            guard let data = content.images.first?.locallyLoadedImage?.pngData() else {
                throw TransferError.nothingToTransfer
            }
            return data
        }
        .suggestedFileName("Image.png")

        FileRepresentation(exportedContentType: .item) { content in
            guard let file = content.files.first else {
                throw TransferError.nothingToTransfer
            }
            return SentTransferredFile(file.url, allowAccessingOriginalFile: false)
        }
        .suggestedFileName { content in
            content.files.first?.name
        }
    }

    /// The content's own words, or `nil` when it has none.
    ///
    /// An attachment contributes only the caption it was given, never its file name: a text payload standing in for
    /// a document would arrive named after it and open as nonsense.
    var transferableText: String? {
        let pieces: [String] = parts.compactMap { part in
            switch part.content {
            case .text(let text):
                text.isEmpty ? nil : text
            case .image, .file:
                part.label
            }
        }
        return pieces.isEmpty ? nil : pieces.joined(separator: "\n")
    }

    /// The content as text for the pasteboard, naming its attachments.
    ///
    /// Unlike ``transferableText`` this does fall back to file names. Pasting is always into something that takes
    /// text, so a name says more there than nothing at all does.
    var pasteboardText: String? {
        let pieces: [String] = parts.compactMap { part in
            switch part.content {
            case .text(let text):
                text.isEmpty ? nil : text
            case .image:
                part.label
            case .file(let file):
                part.label ?? file.name
            }
        }
        return pieces.isEmpty ? nil : pieces.joined(separator: "\n")
    }

    /// Whether there is anything worth offering to the system.
    ///
    /// Every case this reports is one ``transferRepresentation`` can actually serve.
    var canTransfer: Bool {
        transferableText != nil || images.first?.locallyLoadedImage != nil || !files.isEmpty
    }

    /// Puts the content on the system pasteboard.
    ///
    /// `Transferable` covers dragging and sharing, but the pasteboard is still reached through the platform's own
    /// type, so this is the one place that knows about `UIPasteboard`/`NSPasteboard`.
    @MainActor
    func copyToPasteboard() {
        if let text = pasteboardText {
            #if canImport(UIKit)
            UIPasteboard.general.string = text
            #elseif canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #endif
            return
        }
        guard let image = images.first?.locallyLoadedImage else {
            return
        }
        #if canImport(UIKit)
        UIPasteboard.general.image = image
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        #endif
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ChatEntity.Content.File: Transferable {
    /// Offers the file itself, under the name the user knows it by.
    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .item) { file in
            SentTransferredFile(file.url, allowAccessingOriginalFile: false)
        }
        .suggestedFileName { file in
            file.name
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ChatEntity.Content.Image: Transferable {
    /// Offers the image as PNG, whether it is held in memory or behind a data URL.
    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { image in
            guard let data = image.locallyLoadedImage?.pngData() else {
                throw ChatEntity.Content.TransferError.nothingToTransfer
            }
            return data
        }
        .suggestedFileName("Image.png")
    }
}
