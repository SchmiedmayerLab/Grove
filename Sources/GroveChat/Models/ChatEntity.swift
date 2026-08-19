//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// Represents the basic building block of a Grove ``Chat``.
///
/// A ``ChatEntity`` can be thought of as a single message entity within a ``Chat``.
/// It consists of a ``ChatEntity/Role-swift.enum``, a unique identifier, a timestamp in the form of a `Date`, as well as
/// the ``ChatEntity/content`` making up the message itself.
/// The ``ChatEntity/complete`` flag indicates whether the current state of the ``ChatEntity`` is final,
/// i.e. whether the content will not be updated anymore.
///
/// ## Topics
///
/// ### Initializers
/// - ``init(role:content:complete:citations:id:date:)``
/// - ``init(role:text:complete:id:date:)``
/// - ``init(role:image:complete:id:date:)``
@available(iOS 18, macOS 15, watchOS 11, *)
 public struct ChatEntity: Hashable, Identifiable, Codable, Sendable {
    /// Indicates which ``ChatEntity/Role-swift.enum`` is associated with a ``ChatEntity``.
     public enum Role: Hashable, Codable, Sendable {
        case user
        case assistant(AssistantMessageKind)
        case hidden(type: ChatEntity.HiddenMessageType)

        /// The kind of message an ``ChatEntity/Role-swift.enum/assistant(_:)`` entity carries.
        public enum AssistantMessageKind: Hashable, Codable, Sendable {
            /// The assistant's actual answer.
            case response
            /// A tool the assistant asked to invoke.
            case toolCall
            /// The result of a tool invocation, handed back to the assistant.
            case toolResponse
            /// A reasoning phase, with the dates bounding it once they are known.
            case thinking(startDate: Date?, endDate: Date?)
        }

        var rawValue: String {
            switch self {
            case .user: "user"
            case .assistant(.response): "assistant"
            case .assistant(.toolCall): "assistant_tool_call"
            case .assistant(.toolResponse): "assistant_tool_response"
            case .assistant(.thinking): "assistant_thinking"
            case .hidden(let type): "hidden_\(type.name)"
            }
        }
    }

    /// What a message is made of, in the order it is shown.
    ///
    /// Content is an ordered list of ``Part``s rather than a single kind, because a message routinely carries more
    /// than one: a photo and a caption, several files, an answer and the image it produced. Both the OpenAI API and
    /// Apple's `FoundationModels` model a message the same way, so this shape survives contact with either.
    ///
    /// The common cases stay one-liners — ``text(_:)`` builds text content, ``text`` reads it back — while
    /// ``parts`` is there when the exact composition matters.
    ///
    /// ```swift
    /// ChatEntity(role: .user, content: .text("What is this?"))
    /// ChatEntity(role: .user, content: .images([.image(photo)], text: "What is this?"))
    /// ```
    ///
    /// ## Topics
    ///
    /// ### Building content
    /// - ``text(_:)``
    /// - ``image(_:)``
    /// - ``images(_:text:)``
    /// - ``file(_:)``
    /// - ``init(_:)``
    ///
    /// ### Reading content
    /// - ``text``
    /// - ``images``
    /// - ``files``
    /// - ``parts``
    public struct Content: Hashable, Sendable {
        /// What this part actually is.
        public enum PartKind: Hashable, Sendable {
            /// Markdown-formatted text.
            case text(String)
            /// An image, attached by the user or produced by the assistant.
            case image(Image)
            /// A file, attached by the user.
            case file(File)
        }


        /// One piece of a message.
        ///
        /// Carries an identity of its own so that SwiftUI can keep a part in place while the message around it
        /// grows, which is what streaming does to an assistant answer.
        public struct Part: Identifiable, Sendable {
            public let id: UUID
            /// What this part is.
            public var content: PartKind
            /// What assistive technologies read in place of the part, where its content is not text.
            public var label: String?

            /// - Parameters:
            ///   - content: What this part is.
            ///   - label: What assistive technologies should read instead of the content itself.
            ///   - id: The part's identity, defaulting to a fresh one.
            public init(_ content: PartKind, label: String? = nil, id: UUID = .init()) {
                self.content = content
                self.label = label
                self.id = id
            }

            /// A part with the identity it would have as the `index`th part of the entity with this id.
            ///
            /// Content is projected fresh from the conversation every time it is read, so a part that took a new
            /// identity each time would tell SwiftUI the whole message had been replaced on every keystroke of a
            /// streamed answer. Deriving the identity from something stable keeps the view in place.
            package init(_ content: PartKind, label: String? = nil, entityID: UUID, index: Int) {
                self.content = content
                self.label = label
                self.id = Self.derivedID(entityID: entityID, index: index)
            }

            /// Folds a part's position into the entity's id, so the result is stable and unique within a message.
            private static func derivedID(entityID: UUID, index: Int) -> UUID {
                var bytes = withUnsafeBytes(of: entityID.uuid) { Array($0) }
                withUnsafeBytes(of: UInt64(truncatingIfNeeded: index).littleEndian) { indexBytes in
                    for offset in 0..<8 {
                        bytes[8 + offset] ^= indexBytes[offset]
                    }
                }
                return UUID(uuid: (
                    bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                    bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
                ))
            }
        }

        /// An image, e.g. one the user attached to their message, or one the assistant generated.
        public enum Image: Hashable, Sendable {
            case image(PlatformImage)
            case url(URL)
        }

        /// A file the user attached.
        ///
        /// The `url` is a copy the app owns: a picked file's own URL is security-scoped and short-lived, while
        /// previewing and uploading both need one that outlives the picker.
        public struct File: Hashable, Codable, Sendable {
            /// The file's name, as shown to the user.
            public var name: String
            /// Where the app's copy of the file lives.
            public var url: URL
            /// The file's uniform type identifier, if it is known.
            ///
            /// A `String` rather than a `UTType`, so that the model stays Foundation-only and builds anywhere.
            public var contentTypeIdentifier: String?

            public init(name: String, url: URL, contentTypeIdentifier: String? = nil) {
                self.name = name
                self.url = url
                self.contentTypeIdentifier = contentTypeIdentifier
            }
        }

        /// The parts making up the content, in the order they are shown.
        public private(set) var parts: [Part]

        /// The content's text, if it has any.
        ///
        /// Several text parts read as one paragraph run, which is how a model that emits its answer in pieces is
        /// meant to be shown.
        public var text: String? {
            let text = parts
                .compactMap { part in
                    if case .text(let text) = part.content { text } else { nil }
                }
                .joined()
            return text.isEmpty ? nil : text
        }

        /// The content's images, in order. Empty for content that carries none.
        public var images: [Image] {
            parts.compactMap { part in
                if case .image(let image) = part.content { image } else { nil }
            }
        }

        /// The content's files, in order. Empty for content that carries none.
        public var files: [File] {
            parts.compactMap { part in
                if case .file(let file) = part.content { file } else { nil }
            }
        }

        /// Whether the content carries anything other than text.
        public var hasAttachments: Bool {
            parts.contains { part in
                if case .text = part.content { false } else { true }
            }
        }

        /// Whether there is nothing to show.
        public var isEmpty: Bool {
            parts.allSatisfy { part in
                if case .text(let text) = part.content { text.isEmpty } else { false }
            }
        }

        /// Creates content from the given parts.
        public init(_ parts: [Part] = []) {
            self.parts = []
            for part in parts {
                append(part)
            }
        }

        /// Markdown-formatted text.
        public static func text(_ text: some StringProtocol) -> Self {
            Self([Part(.text(String(text)))])
        }

        /// A single image, without accompanying text.
        public static func image(_ image: Image) -> Self {
            Self([Part(.image(image))])
        }

        /// Images, with optional accompanying Markdown-formatted text.
        public static func images(_ images: [Image], text: String? = nil) -> Self {
            var parts = images.map { Part(.image($0)) }
            if let text, !text.isEmpty {
                parts.append(Part(.text(text)))
            }
            return Self(parts)
        }

        /// A single file, without accompanying text.
        public static func file(_ file: File) -> Self {
            Self([Part(.file(file))])
        }

        /// Adds a part to the end of the content.
        ///
        /// Text added onto text extends the part already there rather than starting another, so that content never
        /// accumulates the fragments a streamed answer arrives in.
        public mutating func append(_ part: Part) {
            if case .text(let text) = part.content,
               case .text(let existing) = parts.last?.content {
                parts[parts.endIndex - 1].content = .text(existing + text)
                return
            }
            parts.append(part)
        }
    }


    /// Unique identifier of the ``ChatEntity``.
    public var id: UUID
    /// The creation date of the ``ChatEntity``.
    public var date: Date
    /// ``ChatEntity/Role-swift.enum`` associated with the ``ChatEntity``.
    public var role: Role
    /// Content of the ``ChatEntity``.
    public var content: Content
    /// Indicates if the ``ChatEntity`` is complete and will not receive any additional content.
    public var complete: Bool
    /// Where the message's content came from, for an answer the assistant sourced.
    public var citations: [Citation]


    /// Creates a ``ChatEntity`` which is the building block of a Grove ``Chat``.
    ///
    /// - Parameters:
    ///    - role: ``ChatEntity/Role-swift.enum`` associated with the ``ChatEntity``.
    ///    - content: Content of the ``ChatEntity``.
    ///    - complete: Indicates if the content of the ``ChatEntity`` is complete and will not receive any additional content. Defaults to `true`.
    ///    - citations: Where the message's content came from, for an answer the assistant sourced. Defaults to none.
    ///    - id: Unique identifier of the ``ChatEntity``, defaults to a randomly assigned id.
    ///    - date: Timestamp on when the ``ChatEntity`` was originally created, defaults to the current time.
    public init(
        role: Role,
        content: Content,
        complete: Bool = true,
        citations: [Citation] = [],
        id: UUID = .init(),
        date: Date = .now
    ) {
        self.role = role
        self.content = content
        self.complete = complete
        self.citations = citations
        self.id = id
        self.date = date
    }

    /// Creates a ``ChatEntity`` with text content.
    ///
    /// - Parameters:
    ///    - role: ``ChatEntity/Role-swift.enum`` associated with the ``ChatEntity``.
    ///    - text: `String`-based content of the ``ChatEntity``. Can contain Markdown-formatted text.
    ///    - complete: Indicates if the content of the ``ChatEntity`` is complete and will not receive any additional content. Defaults to `true`.
    ///    - id: Unique identifier of the ``ChatEntity``, defaults to a randomly assigned id.
    ///    - date: Timestamp on when the ``ChatEntity`` was originally created, defaults to the current time.
    public init(
        role: Role,
        text: some StringProtocol,
        complete: Bool = true,
        id: UUID = .init(),
        date: Date = .now
    ) {
        self.init(role: role, content: .text(String(text)), complete: complete, id: id, date: date)
    }

    /// Creates a ``ChatEntity`` with image content.
    ///
    /// - Parameters:
    ///    - role: ``ChatEntity/Role-swift.enum`` associated with the ``ChatEntity``.
    ///    - image: The image making up the ``ChatEntity``.
    ///    - complete: Indicates if the content of the ``ChatEntity`` is complete and will not receive any additional content. Defaults to `true`.
    ///    - id: Unique identifier of the ``ChatEntity``, defaults to a randomly assigned id.
    ///    - date: Timestamp on when the ``ChatEntity`` was originally created, defaults to the current time.
    public init(
        role: Role,
        image: PlatformImage,
        complete: Bool = true,
        id: UUID = .init(),
        date: Date = .now
    ) {
        self.init(role: role, content: .image(.image(image)), complete: complete, id: id, date: date)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ChatEntity.Content: RandomAccessCollection {
    public typealias Element = Part
    public typealias Index = Int

    public var startIndex: Int { parts.startIndex }
    public var endIndex: Int { parts.endIndex }

    public subscript(position: Int) -> Part {
        parts[position]
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ChatEntity.Content: Codable {
    private enum CodingKeys: CodingKey {
        case parts
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let parts = try container.decode([Part].self, forKey: .parts)
        guard !parts.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .parts,
                in: container,
                debugDescription: "A message has to be made of something; found no parts."
            )
        }
        self.init(parts)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(parts, forKey: .parts)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ChatEntity.Content.Part: Hashable {
    /// Two parts are the same when they say the same thing.
    ///
    /// Identity is deliberately left out: it exists so SwiftUI can keep a view in place, while equality answers
    /// whether the conversation changed. Folding identity in would make every re-projection look like a change.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.content == rhs.content && lhs.label == rhs.label
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(content)
        hasher.combine(label)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ChatEntity.Content.Part: Codable {
    private enum CodingKeys: CodingKey {
        case id, label, text, image, file
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let label = try container.decodeIfPresent(String.self, forKey: .label)

        if let text = try container.decodeIfPresent(String.self, forKey: .text) {
            self.init(.text(text), label: label, id: id)
        } else if let image = try container.decodeIfPresent(ChatEntity.Content.Image.self, forKey: .image) {
            self.init(.image(image), label: label, id: id)
        } else if let file = try container.decodeIfPresent(ChatEntity.Content.File.self, forKey: .file) {
            self.init(.file(file), label: label, id: id)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .text,
                in: container,
                debugDescription: "A part carries text, an image or a file; found none of them."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(label, forKey: .label)
        switch content {
        case .text(let text):
            try container.encode(text, forKey: .text)
        case .image(let image):
            try container.encode(image, forKey: .image)
        case .file(let file):
            try container.encode(file, forKey: .file)
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ChatEntity.Content.Image: Codable {
    private enum CodingKeys: CodingKey, CaseIterable {
        case data, url
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let url = try container.decodeIfPresent(URL.self, forKey: .url) {
            self = .url(url)
        } else if let data = try container.decodeIfPresent(Data.self, forKey: .data) {
            guard let image = PlatformImage(data: data) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .data,
                    in: container,
                    debugDescription: "Unable to decode image data into '\(PlatformImage.self)'"
                )
            }
            self = .image(image)
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.url,
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "Expected either of \(CodingKeys.allCases.map { "'\($0)'" }.joined(separator: ", "))"
                )
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .url(let url):
            try container.encode(url, forKey: .url)
        case .image(let image):
            guard let pngData = image.pngData() else {
                throw EncodingError.invalidValue(image, .init(codingPath: container.codingPath, debugDescription: "Unable to obtain PNG data"))
            }
            try container.encode(pngData, forKey: .data)
        }
    }
}
