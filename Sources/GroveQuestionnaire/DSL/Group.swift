//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// A group of items within a section (FHIR item type `group`).
///
/// Groups structure a page without splitting it: the title introduces the questions inside
/// the group, and a condition placed on the group gates all of them at once.
///
/// ```swift
/// Section("phq9", title: "PHQ-9") {
///     Group("recent-mood", title: "Over the last two weeks…") {
///         littleInterest
///         feelingDown
///     }
///     .enabledWhen(screener.selected(.yes))
/// }
/// ```
///
/// Groups nest, and the questions inside one remain ordinary members of the section; the
/// nesting surfaces in the exported FHIR questionnaire and in the collected response.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct Group: QuestionnaireComponent {
    public var _core = ComponentCore() // swiftlint:disable:this identifier_name
    let id: String
    let title: String
    let content: [any QuestionnaireComponent]

    /// Creates a group of items.
    /// - parameter id: The group's linkId.
    /// - parameter title: The group's displayed title.
    /// - parameter content: The items the group encloses.
    public init(_ id: String, title: String = "", @SectionContentBuilder content: () -> [any QuestionnaireComponent]) {
        self.id = id
        self.title = title
        self.content = content()
    }

    public func _makeTasks() -> [Questionnaire.Task] { // swiftlint:disable:this identifier_name
        let group = Questionnaire.Task.Group(
            id: id,
            title: title,
            shortTitle: _core.shortTitle,
            condition: _core.enabledCondition
        )
        return content.flatMap { $0._makeTasks() }.map { task in
            var task = task
            task.groupPath.insert(group, at: 0)
            return task
        }
    }
}


/// A group is nothing but a title and a condition over the items it encloses, so the modifiers
/// describing an item that collects an answer are unavailable rather than quietly dropped.
@available(iOS 18, macOS 15, watchOS 11, *)
extension Group {
    /// Unavailable group modifier that diagnoses optional groups.
    @available(*, unavailable, message: "A group collects no answer; mark the questions inside it optional instead")
    public func optional(_: Bool = true) -> Self { self }

    /// Unavailable group modifier that diagnoses read-only groups.
    @available(*, unavailable, message: "A group collects no answer; mark the questions inside it read-only instead")
    public func readOnly(_: Bool = true) -> Self { self }

    /// Unavailable group modifier that diagnoses hidden groups.
    @available(*, unavailable, message: "A group is not rendered on its own; hide the questions inside it instead")
    public func hidden(_: Bool = true) -> Self { self }

    /// Unavailable group modifier that diagnoses subtitles on groups.
    @available(*, unavailable, message: "A group carries only its title; put the explanation on an Instruction inside it")
    public func subtitle(_: String) -> Self { self }

    /// Unavailable group modifier that diagnoses help text on groups.
    @available(*, unavailable, message: "A group carries only its title; put the guidance on an Instruction inside it")
    public func help(_: String) -> Self { self }

    /// Unavailable group modifier that diagnoses prefixes on groups.
    @available(*, unavailable, message: "A group carries only its title; number the questions inside it instead")
    public func prefix(_: String) -> Self { self }

    /// Unavailable group modifier that diagnoses media on groups.
    @available(*, unavailable, message: "A group carries only its title; attach the media to an item inside it")
    public func media(_: Questionnaire.Task.Media) -> Self { self }

    /// Unavailable group modifier that diagnoses calculated groups.
    @available(*, unavailable, message: "A group collects no answer; compute the value on a question inside it")
    public func calculated(_: ScoreExpression) -> Self { self }

    /// Unavailable group modifier that diagnoses constraints on groups.
    @available(*, unavailable, message: "A group collects no answer; constrain the questions inside it")
    public func constraint(_: String, message _: String) -> Self { self }
}
