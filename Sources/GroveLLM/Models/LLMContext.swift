//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// Represents the context of an ``LLMSession``.
///
/// An ``LLMContext`` is an ordered collection of the messages and other items that make up the conversation with the LLM.
/// It also provides operations for working with this context, for example to add or update entities.
///
/// ``LLMContext`` should be thought of as an "append-only" type, in that most of its operations will either add an entirely
/// new entity to the context, or will append content to the last, i.e. most recent, entity.
///
/// ## Topics
///
/// ### Initializers
/// - ``init()``
/// - ``init(_:)``
/// - ``init(systemMessages:)``
/// - ``init(arrayLiteral:)``
///
/// ### Operations
/// - ``append(systemMessage:to:id:)``
/// - ``append(userMessage:id:date:interactionId:)``
/// - ``append(assistantOutputDelta:isComplete:interactionId:)``
/// - ``markAssistantOutputCompleted()``
/// - ``append(toolCalls:interactionId:)``
/// - ``append(toolCallResponse:for:withId:interactionId:)``
/// - ``clear(keepLeadingSystemMessages:)``
@available(iOS 18, macOS 15, watchOS 11, *)
public struct LLMContext: Hashable, Sendable {
    @usableFromInline var storage: [LLMContextEntity]

    /// Creates a new, empty context.
    public init() {
        storage = []
    }

    /// Creates a context from a sequence of context entities.
    public init(_ elements: some Sequence<LLMContextEntity>) {
        storage = Array(elements)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMContext: Codable {
    /// Decodes from the plain entity array the previous `LLMContext` typealias encoded to.
    public init(from decoder: any Decoder) throws {
        self.init(try [LLMContextEntity](from: decoder))
    }

    /// Encodes as a plain entity array, matching the previous `LLMContext` typealias.
    public func encode(to encoder: any Encoder) throws {
        try storage.encode(to: encoder)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMContext: ExpressibleByArrayLiteral {
    /// Creates a context from an array literal.
    public init(arrayLiteral elements: LLMContextEntity...) {
        self.init(elements)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMContext: RandomAccessCollection, RangeReplaceableCollection, MutableCollection {
    public var startIndex: Int {
        storage.startIndex
    }

    public var endIndex: Int {
        storage.endIndex
    }

    public mutating func replaceSubrange(
        _ subrange: Range<Int>,
        with newElements: some Collection<LLMContextEntity>
    ) {
        storage.replaceSubrange(subrange, with: newElements)
    }

    public subscript(position: Int) -> LLMContextEntity {
        get {
            storage[position]
        }
        set {
            storage[position] = newValue
        }
    }
}


// MARK: Context Operations

@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMContext {
    /// Creates a context from a sequence of system messages.
    public init(systemMessages: some Sequence<String>) {
        self.init(systemMessages.map { message in
            LLMContextEntity(role: .system, content: message, complete: true)
        })
    }

    /// Clears the context.
    ///
    /// - parameter keepLeadingSystemMessages: Whether system messages that appear at the beginning of the context should be kept.
    ///     System messages that are preceded by a non-system-message entity will always be removed.
    public mutating func clear(keepLeadingSystemMessages: Bool) {
        if keepLeadingSystemMessages {
            storage = Array(storage.prefix { $0.role == .system })
        } else {
            storage.removeAll()
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMContext {
    /// Controls system prompt insertion.
    public enum SystemMessageInsertDestination: Hashable, Sendable {
        /// The new system message should be appended to the leading system messages within the context, i.e. inserted after the last leading system message.
        case leadingSystemMessages
        /// The system message should be appended at the end of the whole context.
        case wholeContext
    }


    /// Appends a system prompt to the context.
    ///
    /// - parameter systemMessage: The actual prompt that should be added.
    /// - parameter position: Where the prompt should be placed within the context.
    public mutating func append(
        systemMessage: some StringProtocol,
        to position: SystemMessageInsertDestination,
        id: UUID = .init()
    ) {
        let entity = LLMContextEntity(id: id, role: .system, content: systemMessage, complete: true)
        switch position {
        case .leadingSystemMessages:
            // Only the uninterrupted run at the start counts — a system message injected mid-conversation
            // must not pull new leading prompts down to its position.
            storage.insert(entity, at: storage.prefix(while: { $0.role == .system }).count)
        case .wholeContext:
            storage.append(entity)
        }
    }

    /// Records a system message under an identifier, replacing whatever was recorded under it before.
    ///
    /// Instructions that change as a conversation runs — what a caller wants the model to keep doing — belong
    /// to one entity that is rewritten, not to a new one each time. Rewriting also leaves the entity count
    /// alone, which is what tells a transport carrying server-side state that the conversation it already
    /// submitted still holds.
    ///
    /// - Parameters:
    ///   - systemMessage: The instruction to record.
    ///   - id: Identifies the instruction, so a later call replaces it rather than adding another.
    ///   - position: Where a first recording is placed.
    public mutating func set(
        systemMessage: some StringProtocol,
        id: UUID,
        to position: SystemMessageInsertDestination = .wholeContext
    ) {
        guard let index = firstIndex(where: { $0.id == id }) else {
            append(systemMessage: systemMessage, to: position, id: id)
            return
        }
        self[index].content = String(systemMessage)
    }

    /// Appends a new user message entity to the end of the context.
    public mutating func append(
        userMessage: some StringProtocol,
        id: UUID = .init(),
        date: Date = .now,
        interactionId: LLMInteractionId? = nil
    ) {
        storage.append(.init(id: id, date: date, role: .user, interactionId: interactionId, content: userMessage, complete: true))
    }

    /// Appends an assistant output delta to the context, creating a new entity if necessary.
    public mutating func append(
        assistantOutputDelta delta: some StringProtocol,
        isComplete: Bool,
        interactionId: LLMInteractionId? = nil
    ) {
        if let last, last.role == .assistant, last.interactionId == interactionId, !last.complete {
            self[endIndex - 1].content.append(contentsOf: delta)
            if isComplete {
                markCompleted(at: endIndex - 1)
            }
        } else {
            storage.append(.init(role: .assistant, interactionId: interactionId, content: delta, complete: isComplete))
        }
    }

    /// Appends an image the assistant produced as a message of its own.
    ///
    /// Text the model writes before or after it keeps streaming into separate assistant entities, so the chat shows
    /// the picture between the passages it belongs to.
    package mutating func append(assistantImage image: LLMContextEntity._ImageContent, interactionId: LLMInteractionId? = nil) {
        storage.append(.init(_role: .assistant, _imageContent: image, interactionId: interactionId))
    }

    /// Records where an assistant answer drew from.
    ///
    /// Citations arrive after the text they belong to, so they are merged onto the answer already in the context
    /// rather than appended as something of their own. Sources repeat across a turn — a model cites the same page
    /// for several sentences — so duplicates collapse, keeping the order they were first seen in.
    public mutating func append(citations: [LLMCitation], interactionId: LLMInteractionId? = nil) {
        // A session that does not inject its own output leaves the consumer to append the answer, and the consumer
        // has no interaction id to stamp on it. Falling back to the trailing assistant message keeps sources
        // working in that mode, which is the default one.
        guard !citations.isEmpty,
              let index = lastIndex(where: { $0.role == .assistant && $0.interactionId == interactionId })
                ?? lastIndex(where: { $0.role == .assistant }) else {
            return
        }
        var merged = storage[index].citations ?? []
        var seen = Set(merged.map(\.source))
        for citation in citations where seen.insert(citation.source).inserted {
            merged.append(citation)
        }
        storage[index].citations = merged.isEmpty ? nil : merged
    }

    /// Marks the latest context entity as completed, if it is an assistant message.
    public mutating func markAssistantOutputCompleted() {
        if let last, last.role == .assistant, !last.complete {
            markCompleted(at: endIndex - 1)
        }
    }

    /// Finalizes the entity at `index`, stamping when its streaming ended.
    private mutating func markCompleted(at index: Int) {
        self[index].complete = true
        self[index].completionDate = .now
    }

    /// Appends a ``LLMContextEntity/Role-swift.enum/toolCalls(_:)`` entity to the context.
    public mutating func append(toolCalls: [LLMContextEntity.ToolCall], interactionId: LLMInteractionId? = nil) {
        storage.append(.init(role: .toolCalls(toolCalls), interactionId: interactionId, content: "", complete: true))
    }

    /// Appends a tool call response entity to the context.
    public mutating func append(
        toolCallResponse response: some StringProtocol,
        for functionName: String,
        withId functionId: String,
        interactionId: LLMInteractionId? = nil
    ) {
        storage.append(.init(
            role: .toolCallResponse(id: functionId, name: functionName),
            interactionId: interactionId,
            content: response,
            complete: true
        ))
    }
}


// MARK: Thinking

@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMContext {
    /// Ensures there is an in-progress ``LLMContextEntity/Role-swift.enum/assistantThinking`` entity at the end of the context.
    ///
    /// - parameter interactionId: The interaction this thinking phase belongs to. Used when creating a new entity.
    package mutating func beginAssistantThinkingPlaceholder(with interactionId: LLMInteractionId?) {
        if let last, last.role == .assistantThinking, !last.complete {
            return
        }
        storage.append(.init(role: .assistantThinking, interactionId: interactionId, content: "", complete: false))
    }

    /// Appends a thinking delta to the latest ``LLMContextEntity/Role-swift.enum/assistantThinking`` entry, or starts a new one.
    ///
    /// Use ``beginAssistantThinkingPlaceholder(with:)`` to mark the boundary between reasoning summary parts;
    /// this method then appends incoming deltas onto the active thinking entity.
    package mutating func append(
        assistantThinkingDelta delta: some StringProtocol,
        isComplete: Bool = false,
        interactionId: LLMInteractionId? = nil
    ) {
        // A finalized thinking entity is treated as closed: a new delta starts a new entity instead of
        // appending to a finalized record or demoting it back to incomplete.
        if let last, last.role == .assistantThinking, !last.complete, last.interactionId == interactionId {
            self[endIndex - 1].content.append(contentsOf: delta)
            if isComplete {
                markCompleted(at: endIndex - 1)
            }
        } else {
            storage.append(.init(role: .assistantThinking, interactionId: interactionId, content: delta, complete: isComplete))
        }
    }

    /// Finalizes all in-progress ``LLMContextEntity/Role-swift.enum/assistantThinking`` entries of the interaction.
    ///
    /// Entries that received content are marked ``LLMContextEntity/complete``; placeholders that never received
    /// any are removed — a non-reasoning model opens one per response, and an empty "thought" is not worth a row.
    package mutating func completeAssistantThinkingStreaming(for interactionId: LLMInteractionId) {
        for index in indices.reversed()
            where self[index].interactionId == interactionId && self[index].role == .assistantThinking && !self[index].complete {
            if self[index].content.isEmpty {
                storage.remove(at: index)
            } else {
                markCompleted(at: index)
            }
        }
    }

    /// Removes the trailing ``LLMContextEntity/Role-swift.enum/assistantThinking`` entity, if it is still in-progress.
    package mutating func removeIncompleteAssistantThinking(for interactionId: LLMInteractionId) {
        if let last, last.role == .assistantThinking, !last.complete, last.interactionId == interactionId {
            storage.removeLast()
        }
    }
}
