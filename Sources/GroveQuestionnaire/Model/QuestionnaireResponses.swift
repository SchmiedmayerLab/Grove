//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import Observation
private import OSLog


/// Stores and manages responses to a questionnaire.
///
/// ## Topics
///
/// ### Instance Properties
/// - ``id``
/// - ``questionnaire``
/// - ``responses``
///
/// ### Path Utilities
/// - ``ResponsesPath``
/// - ``ResponsePath``
/// - ``ResponsePathComponent``
///
/// ### Custom Response Support
/// - ``CustomResponseValueProtocol``
///
/// ### Response Data Types
/// - ``Response``
/// - ``ChoiceResponse``
/// - ``ImageAnnotation``
/// - ``CollectedAttachment``
@available(iOS 18, macOS 15, watchOS 11, *)
@Observable
public final class QuestionnaireResponses: Identifiable {
    /// The responses object's variant.
    ///
    /// There are two kinds of ``QuestionnaireResponses`` instances:
    /// 1. Root-level:
    ///     Owns a ``Responses`` object, which contains all responses collected for a questionnaire.
    /// 2. Nested/Inner-level:
    ///     Provides a scoped view into another ``QuestionnaireResponses`` instance.
    ///     In this case, the variant carries, in addition to the parent instance, a ``ResponsesPath`` connecting the current instance to its parent.
    ///     This is used when dealing with nested questions.
    ///     For example, a ``QuestionnaireResponses`` in
    ///
    /// This approach (of having the root/nested variant) is used to provide a common interface for accessing task responses,
    /// regardless of whether they are top-level tasks, or nested within some other response.
    /// In both cases, we can simply inject a ``QuestionnaireResponses`` instance into the SwiftUI view hierarchy,
    /// and the ``QuestionnaireSectionView`` will be able to work with it.
    ///
    /// Additionally, this approach allows us to have the type work correctly with the `Observation` framework, which is required for SwiftUI to properly trigger view updates.
    enum Variant {
        /// The root ``QuestionnaireResponses`` instance, which stores all responses.
        case root(Responses)
        /// A view into another ``QuestionnaireResponses`` instances, scoped to see only the responses at a specific path.
        case view(parent: QuestionnaireResponses, pathFromParent: ResponsesPath)
    }
    
    /// An id identifying this responses instance
    public let id: UUID
    
    /// The questionnaire from which these responses were collected.
    public let questionnaire: Questionnaire
    
    private(set) var _variant: Variant { // swiftlint:disable:this identifier_name
        didSet {
            switch (oldValue, _variant) {
            case (.root, .root), (.view, .view):
                // ok
                break
            case (.root, .view), (.view, .root):
                preconditionFailure("Detected invalid variant kind change in \(Self.self)")
            }
            switch _variant {
            case .root(let responses):
                let sanitized = responses.sanitized() ?? Responses()
                if sanitized != responses {
                    _variant = .root(sanitized)
                }
                recalculateExpressions()
            case .view:
                break
            }
        }
    }

    /// Guards ``recalculateExpressions()`` against re-entrancy: storing a calculated
    /// value mutates the responses, which triggers the observer again.
    private var isRecalculating = false

    /// The authored expressions that failed while these responses were collected.
    ///
    /// An expression that throws is a defect in the instrument, not something the
    /// participant did: the evaluator refuses to guess, so the failure is kept here (and
    /// logged) instead of being read as "the condition did not hold". Each expression is
    /// recorded once. Not observed — conditions are evaluated while views render.
    @ObservationIgnored public private(set) var expressionFailures: [ExpressionFailure] = []
    
    var pathFromRoot: ResponsesPath {
        switch _variant {
        case .root:
            ResponsesPath()
        case let .view(parent, pathFromParent):
            parent.pathFromRoot.appending(pathFromParent)
        }
    }
    
    /// The responses collected from the questionnaire.
    public internal(set) var responses: Responses {
        get {
            switch _variant {
            case .root(let responses):
                responses
            case let .view(parent, pathFromParent):
                parent.responses[pathFromParent]
            }
        }
        set {
            switch _variant {
            case .root:
                _variant = .root(newValue)
            case let .view(parent, pathFromParent):
                parent.responses[pathFromParent] = newValue
            }
        }
    }
    
    init(id: UUID = UUID(), questionnaire: Questionnaire) {
        self.id = id
        self.questionnaire = questionnaire
        _variant = .root(Responses())
        // FHIR initial[x] / initialSelected: seed declared starting values, which the
        // user can still edit (and which satisfy required readOnly items).
        for task in questionnaire.sections.lazy.flatMap(\.tasks) {
            if let initialValue = task.initialValue {
                responses[task.id] = .init(value: initialValue)
            }
        }
    }
    
    private init(parent: QuestionnaireResponses, pathFromParent: ResponsesPath) {
        id = parent.id
        questionnaire = parent.questionnaire
        _variant = .view(parent: parent, pathFromParent: pathFromParent)
    }
    
    
    func view(appending path: ResponsesPath) -> Self {
        Self(parent: self, pathFromParent: path)
    }

    /// Recomputes every task with an SDC `calculatedExpression`, in document order,
    /// so score items stay current as the participant answers.
    private func recalculateExpressions() {
        guard !isRecalculating else {
            return
        }
        let calculatedTasks = questionnaire.sections.lazy.flatMap(\.tasks).filter { $0.calculatedExpression != nil }
        guard calculatedTasks.contains(where: { _ in true }) else {
            return
        }
        guard let engine = questionnaire.expressionEngine else {
            // A questionnaire declared in Swift carries no engine until `withExpressionEngine(evaluationInstant:)`
            // attaches one. Saying so beats leaving every computed value empty, which reads as
            // a scoring bug rather than a setup step.
            Self.logger.warning(
                "\(self.questionnaire.metadata.title, privacy: .public) has calculated expressions but no expression engine; call withExpressionEngine(evaluationInstant:) on it before presenting it."
            )
            return
        }
        isRecalculating = true
        defer {
            isRecalculating = false
        }
        for task in calculatedTasks {
            guard let expression = task.calculatedExpression else {
                continue
            }
            do {
                guard let value = try engine.evaluateValue(expression, for: task, in: self) else {
                    continue
                }
                if responses[task.id].value != value {
                    responses[task.id] = .init(value: value)
                }
            } catch {
                recordExpressionFailure(expression, for: task.id, error: error)
            }
        }
    }
}


// MARK: Expression Diagnostics

@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses {
    /// An authored expression that could not be evaluated against the collected responses.
    public struct ExpressionFailure: Hashable, Sendable {
        /// The item carrying the expression, if it was not questionnaire-level.
        public let taskId: Questionnaire.Task.ID?
        /// The expression as authored.
        public let expression: String
        /// What went wrong.
        public let reason: String
    }

    private static let logger = Logger(subsystem: "org.grovealliance.questionnaire", category: "Expressions")

    func recordExpressionFailure(_ expression: String, for taskId: Questionnaire.Task.ID?, error: some Error) {
        switch _variant {
        case .root:
            guard !expressionFailures.contains(where: { $0.taskId == taskId && $0.expression == expression }) else {
                return
            }
            let reason = String(describing: error)
            expressionFailures.append(.init(taskId: taskId, expression: expression, reason: reason))
            Self.logger.error(
                """
                Expression on '\(taskId ?? questionnaire.id, privacy: .public)' failed: \
                \(expression, privacy: .public) — \(reason, privacy: .public)
                """
            )
        case .view(let parent, pathFromParent: _):
            parent.recordExpressionFailure(expression, for: taskId, error: error)
        }
    }
}


// MARK: Completeness

@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses {
    func hasResponse(for task: Questionnaire.Task) -> Bool {
        switch task.kind.variant {
        case .instructional:
            // instructional tasks never collect a response; they are always considered as being complete.
            true
        case .boolean, .choice, .freeText, .dateTime, .numeric, .fileAttachment, .custom:
            responses[task.id].value != .none
        }
    }
    
    
    func isMissingResponse(for task: Questionnaire.Task) -> Bool {
        // NOTE: on platforms without UIKit (eg macOS, which isn't officially supported yet), a required annotate-image
        // task can never satisfy this check; see the non-UIKit branch of `AnnotateImageQuestionKind.makeView(for:using:response:)` for more info.
        // A hidden task is never shown, so it can never block completion.
        !task.isOptional && !task.isHidden && shouldEnable(task: task) && !hasResponse(for: task)
    }
    
    func isMissingResponses(in section: Questionnaire.Section) -> Bool {
        section.tasks.contains { task in
            isMissingResponse(for: task)
        }
    }
    
    /// Determines whether the questionnaire is currently complete in the specified section.
    ///
    /// This function returns `true` iff all currently enabled required tasks have responses, and none of these responses are invalid.
    func isComplete(in section: Questionnaire.Section) -> Bool {
        !isMissingResponses(in: section) && section.tasks.allSatisfy { task in
            // either the task is hidden or disabled, or its response is valid.
            task.isHidden || !shouldEnable(task: task) || validateResponse(for: task).isOk
        }
    }

    /// Returns the first task in the section that currently prevents the section from being complete.
    ///
    /// For example, if a required task is missing a response or its response is invalid, it would get returned.
    func firstTaskPreventingCompletion(of section: Questionnaire.Section) -> Questionnaire.Task? {
        section.tasks.first { task in
            !task.isHidden && (isMissingResponse(for: task) || !validateResponse(for: task).isOk)
        }
    }
    
    /// Determines the next section, taking into account the current responses and task conditions.
    ///
    /// This function automatically skips empty sections, if e.g. a section doesn't contain any tasks, or all of the section's tasks should be skipped, because of their conditions.
    func nextSection(
        after section: Questionnaire.Section,
        in sections: some Collection<Questionnaire.Section>
    ) -> Questionnaire.Section? {
        guard let sectionIdx = sections.firstIndex(of: section) else {
            return nil
        }
        let remainingSections = sections[sectionIdx...].dropFirst()
        return remainingSections.first { section in
            section.tasks.contains { shouldEnable(task: $0) }
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses {
    /// Removes all responses that were collected for tasks that are currently disabled.
    ///
    /// When collecting responses to a questionnaire, whether a task `Y` is enabled or disabled can change even after a response has already been collected for that task,
    /// if the user goes back to a previous task `X` and changes the response there, since `Y`'s ``Questionnaire/Task/enabledCondition`` might depend on the `X`'s response.
    ///
    /// While answering a questionnaire, the ``QuestionnaireResponses`` will keep the response collected for task `Y`, even if a change to `X` would mean that `Y` is no longer enabled;
    /// this ensures that the user doesn't have to re-enter potentially large amounts of data if they (accidentally) change an earlier task's response.
    ///
    /// This function goes through the entire questionnaire, in order, re-evaluates each task's ``Questionnaire/Task/enabledCondition``, and removes all responses whose task's
    /// are no longer enabled.
    func purgeResponsesToDisabledTasks() {
        _purgeResponsesToDisabledTasks(questionnaire.sections.lazy.flatMap(\.tasks))
    }
    
    private func _purgeResponsesToDisabledTasks(_ allTasks: some Sequence<Questionnaire.Task>) {
        for task in allTasks {
            guard shouldEnable(task: task) else {
                responses[task.id] = .init(value: .none)
                continue
            }
            if !responses[task.id].nestedResponses.isEmpty && task.kind.followUpTasks.isEmpty {
                // Found nested responses for a task that doesn't have nested questions
                responses[task.id].nestedResponses.removeAll()
            }
            switch task.kind.variant {
            case .choice(let config):
                for option in config.options {
                    self
                        .view(appending: ResponsesPath().appending(taskId: task.id).appending(choiceOption: option.id))
                        ._purgeResponsesToDisabledTasks(task.kind.followUpTasks)
                }
            case .instructional:
                responses[task.id] = .init(value: .none)
            case .boolean, .freeText, .dateTime, .numeric, .fileAttachment, .custom:
                break
            }
        }
    }
}
