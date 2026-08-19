//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
private import GroveFoundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire {
    /// A unit of work the participant is asked to perform as part of the questionnaire (typically a question being asked)
    public struct Task: Hashable, Identifiable, Sendable {
        /// A group of tasks nested inside a ``Questionnaire/Section`` (FHIR item type `group`).
        ///
        /// Groups structure a page without splitting it: they carry a title and a condition
        /// gating every task inside them, and the tasks themselves stay a flat list on the section.
        public struct Group: Hashable, Identifiable, Sendable {
            /// The group's identifier (FHIR `linkId`).
            public var id: String
            /// The group's user-displayed title (FHIR `item.text`).
            public var title: String
            /// An abbreviated title for constrained displays (SDC `shortText`).
            public var shortTitle: String?
            /// Controls when the group, and with it every task inside it, is enabled.
            public var condition: Condition

            /// Creates a group.
            public init(id: String, title: String = "", shortTitle: String? = nil, condition: Condition = .none) {
                self.id = id
                self.title = title
                self.shortTitle = shortTitle
                self.condition = condition
            }
        }

        /// A code identifying a question (FHIR `item.code`).
        public struct Code: Hashable, Sendable {
            public let system: URL?
            public let code: String
            public let display: String?

            public init(system: URL? = nil, code: String, display: String? = nil) {
                self.system = system
                self.code = code
                self.display = display
            }
        }

        /// Media rendered alongside a task or answer option (SDC `itemMedia`).
        public struct Media: Hashable, Sendable {
            /// The media's raw content (typically an image).
            public let data: Data
            /// The media's MIME content type.
            public let contentType: String
            /// The accessibility description (from the attachment's `title`).
            public let altText: String?

            public init(data: Data, contentType: String, altText: String? = nil) {
                self.data = data
                self.contentType = contentType
                self.altText = altText
            }
        }

        /// The task's unique identifier.
        ///
        /// - Important: Task identifiers must be unique across all tasks in all sections of the questionnaire.
        public var id: String
        /// The task's user-displayed title.
        public var title: String
        /// A short display prefix such as question numbering (FHIR `item.prefix`, e.g. "1a.").
        public var prefix: String?
        /// An abbreviated title for constrained displays (SDC `shortText`).
        public var shortTitle: String?
        /// The task's user-displayed subtitle.
        ///
        /// Set this property to an empty string in order to omit the subtitle.
        public var subtitle: String
        /// A footer text displayed below the task.
        public var footer: String
        /// An image rendered alongside the task (SDC `itemMedia`).
        public var media: Media?
        /// The task's kind
        public var kind: Kind
        /// Whether the user is allowed to skip this task.
        public var isOptional: Bool
        /// Controls when the task is enabled.
        ///
        /// Use ``Questionnaire/Condition/none`` to specify that the task does not have a condition and should always be enabled.
        ///
        /// A task's `enabledCondition` can reference any other task in the questionnaire, including tasks
        /// that appear after this one. Conditions referencing the task they belong to, or forming a
        /// reference cycle, evaluate as if the referenced response were absent.
        /// If this is a nested task, the condition is first evaluated in the current nesting scope (i.e., the preceding nested questions, and their responses);
        /// if it does not evaluate to `true` in this scope, it is evaluated again in the parent scope (where it can access the responses to all preceding tasks as well),
        /// and if necessary in that scope's parent scope, and so on.
        public var enabledCondition: Condition
        /// Whether the task's response is read-only (FHIR `item.readOnly`).
        public var isReadOnly: Bool
        /// Whether the task is hidden from the user (FHIR `questionnaire-hidden`).
        ///
        /// Hidden tasks are not rendered, never block completion, and exist to carry
        /// pre-populated or calculated values; their responses are still exported.
        public var isHidden: Bool
        /// The task's pre-populated starting value (FHIR `item.initial` /
        /// `answerOption.initialSelected`), still editable by the user.
        public var initialValue: QuestionnaireResponses.Response.Value?
        /// The SDC `initialExpression` that supplies the initial value, when imported
        /// from FHIR. It remains distinct from ``initialValue`` so export is lossless.
        public var initialExpression: String?
        /// An expression continuously recomputing this task's value from other answers
        /// (SDC `calculatedExpression`), evaluated by the questionnaire's expression engine.
        public var calculatedExpression: String?
        /// Item-scoped SDC variables, in declaration order.
        public var variables: [Questionnaire.ExpressionVariable]
        /// Authored cross-field validation rules (FHIR `targetConstraint`).
        public var constraints: [Constraint]
        /// The codes identifying the question itself (FHIR `item.code`), carried unchanged.
        ///
        /// Standardised instruments identify their items this way — the LOINC code of a
        /// PHQ-9 question, say — so the codes survive import and export untouched.
        public var codes: [Code]
        /// The element definition this item is derived from (FHIR `item.definition`).
        public var definition: URL?
        /// The (non-page-level) groups enclosing this task, outermost first.
        ///
        /// Empty for ungrouped tasks. The task is only enabled while every enclosing group's
        /// ``Group/condition`` holds, and both the exported questionnaire and a generated
        /// `QuestionnaireResponse` restore the hierarchy from this path.
        public var groupPath: [Group]
        /// The id of the question task this task was nested under in the source FHIR questionnaire.
        ///
        /// `nil` for natively authored and non-nested tasks. Set by the FHIR conversion so a
        /// generated `QuestionnaireResponse` can nest this task's answers beneath its parent.
        public var parentTaskId: Task.ID?

        /// Creates a new task.
        public init(
            id: String,
            title: String,
            prefix: String? = nil,
            shortTitle: String? = nil,
            subtitle: String = "",
            footer: String = "",
            media: Media? = nil,
            kind: Kind,
            isOptional: Bool = false,
            enabledCondition: Condition = .none,
            isReadOnly: Bool = false,
            isHidden: Bool = false,
            initialValue: QuestionnaireResponses.Response.Value? = nil,
            initialExpression: String? = nil,
            calculatedExpression: String? = nil,
            variables: [Questionnaire.ExpressionVariable] = [],
            constraints: [Constraint] = [],
            codes: [Code] = [],
            definition: URL? = nil,
            groupPath: [Group] = [],
            parentTaskId: Task.ID? = nil
        ) {
            self.id = id
            self.title = title
            self.prefix = prefix
            self.shortTitle = shortTitle
            self.subtitle = subtitle
            self.footer = footer
            self.media = media
            self.kind = kind
            self.isOptional = isOptional
            self.enabledCondition = enabledCondition
            self.isReadOnly = isReadOnly
            self.isHidden = isHidden
            self.initialValue = initialValue
            self.initialExpression = initialExpression
            self.calculatedExpression = calculatedExpression
            self.variables = variables
            self.constraints = constraints
            self.codes = codes
            self.definition = definition
            self.groupPath = groupPath
            self.parentTaskId = parentTaskId
        }
    }
}
