//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI
#if Textual
import Textual
#endif


/// Displays the contents of a ``ChatEntity``, without applying any styling based on the context and role of the message.
@available(iOS 18, macOS 15, watchOS 11, *)
struct PlainMessageView: View {
    private let message: ChatEntity
    /// Whether the content sits inside a chat bubble, which decides how much room a caption needs above it.
    private let insideBubble: Bool

    var body: some View {
        // Attachments lead and text follows, whatever order the parts arrived in: a caption belongs under the
        // thing it captions, and a message that interleaved them would read as a jumble at this size.
        VStack(alignment: message.horziontalAlignment, spacing: 0) {
            if !message.content.images.isEmpty {
                AttachedImagesView(images: message.content.images)
            }
            if !message.content.files.isEmpty {
                AttachedFilesView(files: message.content.files)
                    .padding(.top, message.content.images.isEmpty ? 0 : 6)
            }
            if let text = message.content.text, !text.isEmpty {
                MarkdownView(text: text)
                    .frame(maxWidth: .infinity, alignment: message.content.hasAttachments ? .leading : .center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, textTopPadding)
            }
        }
    }

    /// A caption needs clearing from whatever it sits under; text on its own needs nothing.
    private var textTopPadding: CGFloat {
        guard message.content.hasAttachments else {
            return 0
        }
        return insideBubble ? MessageStyleModifier.padding.top : 8
    }

    init(_ message: ChatEntity, insideBubble: Bool = false) {
        self.message = message
        self.insideBubble = insideBubble
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension PlainMessageView {
    /// Renders Markdown-formatted message content.
    struct MarkdownView: View {
        let text: String

        var body: some View {
            #if Textual
            StructuredText(markdown: text)
                .textual.inlineStyle(
                    InlineStyle.gitHub
                        .code(.monospaced, .fontScale(0.85), .backgroundColor(.clear))
                )
                .textual.structuredTextStyle(.gitHub)
            #else
            Text(attributedText)
                .textSelection(.enabled)
            #endif
        }

        #if !Textual
        private var attributedText: AttributedString {
            let options = AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
            return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        }
        #endif
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension PlainMessageView {
    /// Lays images attached to a message out so that they read as part of the conversation.
    ///
    /// A single image keeps its own proportions; several are cut to uniform square tiles, because a grid of
    /// mismatched aspect ratios leaves ragged gaps. Tapping any of them opens the whole set full-screen.
    ///
    /// Images carry no border or shadow of their own — the corners are applied by whoever places this view, since
    /// only the caller knows whether a caption follows inside the same bubble.
    struct AttachedImagesView: View {
        /// Which image the viewer opens on, and whether it is open at all.
        private struct ViewedImage: Identifiable {
            let id: Int
        }
        /// A single image never grows taller than this, so a portrait photo cannot push the conversation away.
        private static let maximumHeight: CGFloat = 320
        /// Matches the bubble's own curve closely enough to sit inside it without looking bolted on.
        private static let cornerRadius: CGFloat = 14
        /// Tiles below this stop shrinking and rewrap instead.
        private static let minimumTileWidth: CGFloat = 108
        private static let spacing: CGFloat = 3

        let images: [ChatEntity.Content.Image]

        @State private var viewedImage: ViewedImage?

        var body: some View {
            Group {
                switch images.count {
                case 0:
                    EmptyView()
                case 1:
                    Self.imageContent(for: images[0], fillingTile: false)
                        .frame(maxHeight: Self.maximumHeight)
                        .clipShape(.rect(cornerRadius: Self.cornerRadius, style: .continuous))
                        .onTapGesture {
                            viewedImage = ViewedImage(id: 0)
                        }
                default:
                    tiles
                }
            }
            .accessibilityElement(children: .contain)
            .sheet(item: $viewedImage) { viewed in
                ChatImageViewer(images: images, startingAt: viewed.id)
            }
        }

        /// Square tiles, so rows line up however the images themselves are proportioned.
        private var tiles: some View {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Self.minimumTileWidth), spacing: Self.spacing)],
                spacing: Self.spacing
            ) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            Self.imageContent(for: image, fillingTile: true)
                        }
                        .clipShape(.rect(cornerRadius: 8, style: .continuous))
                        .contentShape(.rect)
                        .onTapGesture {
                            viewedImage = ViewedImage(id: index)
                        }
                }
            }
        }

        /// The image itself, either fitted to its own proportions or filling a square tile.
        @ViewBuilder
        static func imageContent(for image: ChatEntity.Content.Image, fillingTile: Bool) -> some View {
            Group {
                switch image {
                case .image(let image):
                    resized(Image(platformImage: image), fillingTile: fillingTile)
                case .url(let url):
                    AsyncImage(url: url) { image in
                        resized(image, fillingTile: fillingTile)
                    } placeholder: {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: fillingTile ? 0 : 120)
                    }
                }
            }
            .accessibilityLabel(Text("ATTACHED_IMAGE", bundle: .module))
        }

        @ViewBuilder
        private static func resized(_ image: Image, fillingTile: Bool) -> some View {
            if fillingTile {
                image
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                image
                    .resizable()
                    .scaledToFit()
            }
        }
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            PlainMessageView(ChatEntity(role: .user, text: "User Message!"))
            PlainMessageView(ChatEntity(role: .assistant(.response), text: "Assistant Message!"))
            PlainMessageView(ChatEntity(role: .assistant(.response), text: "A **bold** claim, and some `inline code`."))
            PlainMessageView(ChatEntity(role: .assistant(.toolCall), text: "assistant_tool_call(parameter: value)"))
            PlainMessageView(ChatEntity(role: .assistant(.toolResponse), text: """
            {
                "some": "response"
            }
            """))
        }
        .padding()
    }
}
#endif
