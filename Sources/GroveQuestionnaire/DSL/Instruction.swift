//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Instructional text shown to the participant (FHIR item type `display`).
///
/// The text supports Markdown.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct Instruction: QuestionnaireComponent {
    public var _core = ComponentCore() // swiftlint:disable:this identifier_name
    let id: String
    let text: String

    /// Creates instructional text.
    /// - parameter id: The item's linkId.
    /// - parameter text: The displayed (Markdown-capable) text.
    public init(_ id: String, _ text: String) {
        self.id = id
        self.text = text
    }

    public func _makeTasks() -> [Questionnaire.Task] { // swiftlint:disable:this identifier_name
        var task = Questionnaire.Task(id: id, title: "", kind: .instructional(text))
        _core.apply(to: &task)
        return [task]
    }
}
