//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

import Foundation
import os
import PDFKit
import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
extension ChatView {
    /// Output format of the to-be exported ``Chat``.
    public enum ChatExportFormat {
        /// JSON representation of the ``Chat``
        case json
        /// Textual UTF-8 version of the ``Chat``
        case text
        /// Rendered PDF document of the ``Chat``
        case pdf
    }


    private static let logger = Logger(subsystem: "org.grovealliance", category: "GroveChat")
    private static let encoder: JSONEncoder = {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .prettyPrinted
        jsonEncoder.dateEncodingStrategy = .iso8601
        return jsonEncoder
    }()


    /// The chat exported as `Data`, in the format specified by ``ChatView/ChatExportFormat``.
    @MainActor
    static func export(_ chat: Chat, as format: ChatExportFormat) -> Data? {
        switch format {
        case .json:
            exportToJSON(chat)
        case .text:
            exportToText(chat)
        case .pdf:
            exportToPDF(chat)
        }
    }

    private static func exportToJSON(_ chat: Chat) -> Data? {
        guard let jsonData = try? Self.encoder.encode(chat) else {
            Self.logger.error("The to be exported chat couldn't be encoded to JSON format!")
            return nil
        }
        return jsonData
    }

    private static func exportToText(_ chat: Chat) -> Data? {
        let textData = chat
            .map { entity in
                // Format: <ROLE> (<DATE>): <CONTENT>
                "\(entity.role.rawValue.capitalized) (\(entity.date.formatted())): \(entity.exportedTextContent)"
            }
            .joined(separator: "\n")
            .data(using: .utf8)
        guard let textData else {
            Self.logger.error("The to be exported chat couldn't be encoded in a textual UTF-8 format!")
            return nil
        }
        return textData
    }

    @MainActor
    private static func exportToPDF(_ chat: Chat) -> Data? {
        let renderer = ImageRenderer(content: PDFExportChatView(chat: chat))
        #if !os(macOS)
        var proposedHeightOptional = renderer.uiImage?.size.height
        #else
        var proposedHeightOptional = renderer.nsImage?.size.height
        #endif
        guard let proposedHeight = proposedHeightOptional else {
            Self.logger.error("""
            The to be exported chat couldn't be rendered as a PDF as the height of the rendered page couldn't be determined!
            """)
            return nil
        }
        // Width from US Letter, height requested by the view.
        // Reason: Splitting a view in multiple PDF pages is complex!
        let size = CGSize(width: 72 * 8.5, height: proposedHeight)
        renderer.proposedSize = .init(size)
        #if !os(macOS)
        proposedHeightOptional = renderer.uiImage?.size.height
        #else
        proposedHeightOptional = renderer.nsImage?.size.height
        #endif
        // Need to fetch the page height again as it is adjusted after setting the `proposedSize` on the `ImageRenderer`.
        guard let proposedHeight = proposedHeightOptional else {
            Self.logger.error("""
            The to be exported chat couldn't be rendered as a PDF as the height of the rendered page couldn't be determined!
            """)
            return nil
        }
        var pdfData: Data?
        renderer.render { _, context in
            var box = CGRect(origin: .zero, size: .init(width: size.width, height: proposedHeight))
            guard let mutableData = CFDataCreateMutable(kCFAllocatorDefault, 0),
                  let consumer = CGDataConsumer(data: mutableData),
                  let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else {
                Self.logger.error("The to be exported chat couldn't be rendered as a PDF!")
                pdfData = nil
                return
            }
            pdf.beginPDFPage(nil)
            pdf.translateBy(x: 0, y: 0)
            context(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            pdfData = PDFDocument(data: mutableData as Data)?.dataRepresentation()
        }
        return pdfData
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ChatEntity {
    /// The entity's content, rendered for plain-text export.
    ///
    /// Every part contributes something, in order: an attachment that exports as nothing at all would silently
    /// drop from the transcript.
    fileprivate var exportedTextContent: String {
        content.parts
            .map { part in
                switch part.content {
                case .text(let text): text
                case .image(let image): image.exportDescription
                case .file(let file): "[\(file.name)]"
                }
            }
            .joined(separator: " ")
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ChatEntity.Content.Image {
    fileprivate var exportDescription: String {
        switch self {
        case .image:
            "[image]"
        case .url(let url):
            // Data URLs inline the whole payload; dumping them into a text export helps no one.
            url.scheme == "data" ? "[image]" : "[image: \(url.absoluteString)]"
        }
    }
}


/// As the ``ChatView`` and the ``MessagesView`` include elements that are not supported by the SwiftUI `ImageRenderer`,
/// `PDFExportChatView` serves as a simplified intermediary layer for the export of the ``Chat`` to a PDF.
@available(iOS 18, macOS 15, watchOS 11, *)
private struct PDFExportChatView: View {
    let chat: Chat

    var body: some View {
        // The SwiftUI `ImageRenderer` doesn't support SwiftUI `List`s
        VStack(spacing: 8) {
            ForEach(chat, id: \.self) { entity in
                PDFExportChatMessageView(message: entity)
            }
            Spacer()
        }
        .padding()
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
private struct PDFExportChatMessageView: View {
    let message: ChatEntity

    var body: some View {
        HStack {
            if message.alignment == .trailing {
                Spacer(minLength: 32)
            }
            VStack(alignment: message.horziontalAlignment) {
                contentView
                Group {
                    switch message.role {
                    case .hidden(let type):
                        Text("\(type.name.capitalized) (hidden): \(message.date.formatted())", bundle: .module)
                    default:
                        Text("\(message.role.rawValue.capitalized): \(message.date.formatted())", bundle: .module)
                    }
                }
                .font(.caption)
                .foregroundStyle(.gray)
            }
            if message.alignment == .leading {
                Spacer(minLength: 32)
            }
        }
    }

    @ViewBuilder private var contentView: some View {
        VStack(alignment: message.horziontalAlignment, spacing: 6) {
            ForEach(Array(message.content.images.enumerated()), id: \.offset) { _, image in
                // Data URLs decode synchronously — no network involved — so inline payloads still render in the PDF.
                if let platformImage = image.locallyLoadedImage {
                    Image(platformImage: platformImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .accessibilityHidden(true)
                } else if case .url(let url) = image {
                    Text(url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // A PDF cannot carry the file itself, so it names it. An attachment that exported as nothing at all
            // would leave the transcript quietly misrepresenting what was in the conversation.
            ForEach(message.content.files, id: \.url) { file in
                Label(file.name, systemImage: file.symbolName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let text = message.content.text, !text.isEmpty {
                // NOTE: we intentionally use a `Text` with an `AttributedString` here instead of the `StructuredText` used in the
                // `MessageView`, the reason being that `StructuredText` doesn't render properly during the PDF export.
                Text(attributedString(for: text))
                    .fixedSize(horizontal: false, vertical: true)
                    #if !os(visionOS)
                    .chatMessageStyle(alignment: message.alignment)
                    #else
                    // Workaround setting the user background color to blue for visionOS,
                    // as .accentColor isn't properly set during export with the `ImageRenderer`.
                    .chatMessageStyle(alignment: message.alignment, backgroundColorUserChat: .blue)
                    #endif
            }
        }
    }

    private func attributedString(for text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
