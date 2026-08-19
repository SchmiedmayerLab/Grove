//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
private import GroveFoundation


/// A questionnaire.
///
/// ## Overview
///
/// Questionnaires consist of a sequence of ``Section``s, each of which contains a list of ``Task``s.
/// When using the ``QuestionnaireSheet`` to answer a questionnaire, each section is displayed as a separate page on a `NavigationStack`.
///
/// ### Interoperability
///
/// The `Questionnaire` type is compatible with [FHIR R4 questionnaires](https://hl7.org/fhir/R4/questionnaire.html)
///
///
/// ## Topics
///
/// ### Initializers
/// - ``init(metadata:sections:)``
///
/// ### Instance Properties
/// - ``id``
/// - ``metadata``
/// - ``sections``
///
/// ### Supporting Types
/// - ``Metadata``
/// - ``Section``
/// - ``Task``
@available(iOS 18, macOS 15, watchOS 11, *)
public struct Questionnaire: Hashable, Identifiable, Sendable {
    // NOTE that `Questionnaire` and its related types (Section, Task, etc) currently are **intentionally** not Codable;
    // the reason being that we will potentially make significant changes to the data structures here, which would break
    // the decoding of questionnaires encoded with older versions of the package.

    /// Questionnaire metadata.
    public let metadata: Metadata
    /// The questionnaire's content
    public let sections: [Section]
    /// Evaluates authored expressions (SDC FHIRPath) against the live responses.
    ///
    /// Wired up by the FHIR conversion layer when the source questionnaire uses
    /// expression-based features; excluded from equality and hashing.
    public var expressionEngine: (any QuestionnaireExpressionEngine)?

    public var id: String {
        metadata.id
    }

    /// Creates a questionnaire whose identifiers are known to be unique.
    ///
    /// Authored questionnaires are checked at compile time by ``Instrument()``, so a
    /// collision here is a programmer error and traps. Use ``validated(metadata:sections:)``
    /// for content assembled from data, such as an imported FHIR resource.
    public init(metadata: Metadata, sections: [Section]) {
        self.init(unchecked: metadata, sections: sections)
        do {
            try validate()
        } catch {
            preconditionFailure(error.description)
        }
    }

    private init(unchecked metadata: Metadata, sections: [Section]) {
        self.metadata = metadata
        self.sections = sections
    }

    /// Creates a questionnaire from content whose identifiers may collide, reporting the
    /// collision instead of trapping on it.
    public static func validated(metadata: Metadata, sections: [Section]) throws(IntegrityError) -> Self {
        let questionnaire = Self(unchecked: metadata, sections: sections)
        try questionnaire.validate()
        return questionnaire
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.metadata == rhs.metadata && lhs.sections == rhs.sections
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(metadata)
        hasher.combine(sections)
    }


    /// Creates a functionally identical copy of this questionnaire, with all ``Condition``s simplified.
    func withConditionsSimplified() -> Self {
        var copy = Questionnaire(
            unchecked: metadata,
            sections: sections.map { section in
                var section = section
                section.tasks = section.tasks.map { task in
                    task.withConditionsSimplified()
                }
                return section
            }
        )
        copy.expressionEngine = expressionEngine
        return copy
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire.Task {
    /// Creates a functionally identical copy of this task, with all ``Condition``s simplified.
    func withConditionsSimplified() -> Self {
        var copy = self
        copy.enabledCondition.simplify()
        for index in copy.groupPath.indices {
            copy.groupPath[index].condition.simplify()
        }
        switch copy.kind.variant {
        case .boolean, .dateTime, .freeText, .numeric, .instructional, .fileAttachment:
            break
        case .choice(var config):
            config.followUpTasks = config.followUpTasks.map {
                $0.withConditionsSimplified()
            }
            copy.kind = .choice(config)
        case let .custom(questionKind, config):
            copy.kind = .init(variant: .custom(questionKind: questionKind, config: config.withConditionsSimplified()))
        }
        return copy
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire {
    /// A named FHIRPath expression made available to other questionnaire expressions
    /// through the SDC `variable` extension.
    public struct ExpressionVariable: Hashable, Sendable {
        /// The name used to reference the value from FHIRPath.
        public let name: String
        /// The FHIRPath expression that computes the value.
        public let expression: String

        /// Creates an SDC expression variable.
        public init(name: String, expression: String) {
            self.name = name
            self.expression = expression
        }
    }

    /// Finds the top-level task with the specified id.
    func task(withId taskId: Task.ID) -> Task? {
        sections.lazy.flatMap(\.tasks).first { $0.id == taskId }
    }
    
    /// Obtains the (potentially nested) task at the specified path.
    ///
    /// If the path contains only a single element, this function behaves identical to ``task(withId:)``  and simply returns the top-level task with the specified identifier.
    /// If the path contains multiple elements, the nested task reached via the path is returned.
    /// If the path is invalid, this function returns `nil`.
    ///
    /// - Note: This function does not take a task's ``Task/enabledCondition`` into account;
    ///     it will unconditionally consider all tasks, even if one of the tasks in the path is currently disabled.
    ///
    /// - parameter path: A sequence of ``Task`` identifiers.
    func task(at path: some Sequence<Task.ID>) -> Task? {
        var iterator = path.makeIterator()
        guard var current = iterator.next().flatMap({ task(withId: $0) }) else {
            return nil
        }
        while let nextId = iterator.next() {
            guard let nextTask = current.kind.followUpTasks.first(where: { $0.id == nextId }) else {
                return nil
            }
            current = nextTask
        }
        return current
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire {
    /// The questionnaire's publication lifecycle (FHIR `Questionnaire.status`).
    public enum PublicationLifecycle: String, Hashable, Sendable {
        case draft
        case active
        case retired
        case unknown
    }

    /// How the participant may move through the questionnaire (SDC `entryMode`).
    public enum EntryMode: String, Hashable, Sendable {
        /// Answers are entered in order and earlier answers cannot be revisited.
        case sequential
        /// Earlier answers may be revised, but items cannot be skipped ahead.
        case priorEdit = "prior-edit"
        /// Free navigation (the default).
        case random
    }

    public struct Metadata: Hashable, Sendable {
        /// The questionnaire's unique identifier.
        public let id: String
        /// The questionnaire's identifying URL, if applicable.
        public let url: URL?
        /// The questionnaire's business version (FHIR `Questionnaire.version`), if applicable.
        ///
        /// When present, generated `QuestionnaireResponse`s pin their `questionnaire`
        /// canonical to this version (`url|version`).
        public let version: String?
        /// The questionnaire's user-displayed title.
        public let title: String
        /// Natural-language description of the questionnaire.
        public let explainer: String
        /// The questionnaire's publication lifecycle.
        public let lifecycle: PublicationLifecycle
        /// The instrument's publisher, for attribution of licensed instruments.
        public let publisher: String?
        /// The instrument's copyright notice, for attribution of licensed instruments.
        public let copyright: String?
        /// Administration concerns surfaced during conversion (e.g. the questionnaire is
        /// outside its `effectivePeriod`, or is a draft). Apps decide whether to warn or refuse.
        public let administrationWarnings: [String]
        /// How the participant may move through the questionnaire.
        public let entryMode: EntryMode
        /// Questionnaire-wide SDC variables, in declaration order.
        public let variables: [ExpressionVariable]

        public init(
            id: String,
            url: URL?,
            version: String? = nil,
            title: String,
            explainer: String,
            lifecycle: PublicationLifecycle = .active,
            publisher: String? = nil,
            copyright: String? = nil,
            administrationWarnings: [String] = [],
            entryMode: EntryMode = .random,
            variables: [ExpressionVariable] = []
        ) {
            self.id = id
            self.url = url
            self.version = version
            self.title = title
            self.explainer = explainer
            self.lifecycle = lifecycle
            self.publisher = publisher
            self.copyright = copyright
            self.administrationWarnings = administrationWarnings
            self.entryMode = entryMode
            self.variables = variables
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire {
    /// A group of tasks.
    public struct Section: Hashable, Identifiable, Sendable {
        public var id: String
        public var title: String
        /// An abbreviated title for constrained displays (SDC `shortText`).
        public var shortTitle: String?
        public var tasks: [Task]
        /// The linkId of the top-level FHIR group this section was created from, if any.
        ///
        /// `nil` for natively authored sections and for sections synthesized around
        /// ungrouped top-level FHIR items. When set, a generated `QuestionnaireResponse`
        /// wraps this section's answers in an item with this linkId, mirroring the
        /// questionnaire's structure.
        public var fhirGroupId: String?

        /// Creates a `Section`.
        ///
        /// - parameter id: The section's identifier. Must be unique among all sections within a ``Questionnaire``.
        /// - parameter title: The section's display title.
        /// - parameter shortTitle: An abbreviated title for constrained displays (SDC `shortText`).
        /// - parameter enabledCondition: A ``Questionnaire/Condition`` determining whether the section should be enabled.
        ///     Note that the condition may only reference tasks that precede this section within the questionnaire.
        ///     If the section's `enabledCondition` evaluates to `true`, but all of the section's task ``Questionnaire/Task/enabledCondition``s evaluate to `false`, the section will be skipped entirely.
        /// - parameter tasks: The section's ``Questionnaire/Task``s.
        ///     Note that if a section does not contain any tasks, it may be skipped unconditionally by the ``QuestionnaireSheet``.
        /// - parameter fhirGroupId: The linkId of the FHIR group this section mirrors, if any.
        public init(
            id: String,
            title: String = "",
            shortTitle: String? = nil,
            enabledCondition: Condition = .none,
            tasks: [Task],
            fhirGroupId: String? = nil
        ) {
            self.id = id
            self.title = title
            self.shortTitle = shortTitle
            self.fhirGroupId = fhirGroupId
            // we don't actually support section-level conditions, so instead we simply propagate the condition down into the tasks
            self.tasks = tasks.map { task in
                var task = task
                task.enabledCondition = task.enabledCondition && enabledCondition
                return task
            }
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire.Section {
    func nextEnabledTask(after task: Questionnaire.Task, using responses: QuestionnaireResponses) -> Questionnaire.Task? {
        guard let taskIdx = tasks.firstIndex(of: task) else {
            return nil
        }
        return tasks[taskIdx...].dropFirst().first { !$0.isHidden && responses.shouldEnable(task: $0) }
    }
}
