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
    /// Controls when a task or other questionnaire component should be enabled.
    ///
    /// Conditions allow establishing dependencies between ``Task``s within a ``Questionnaire``,
    /// and can be used to conditionally ask additional questions, based on e.g. a user's response to some other task.
    ///
    /// A condition may reference any other task in the questionnaire, including tasks that appear
    /// after the one it belongs to (matching FHIR's `enableWhen`, which places no ordering
    /// restriction on references). A condition that references its own task, an unknown task, or a
    /// task that is itself currently disabled evaluates as if the referenced response were absent.
    ///
    /// ## Topics
    ///
    /// ### Conditions
    /// - ``not(_:)``
    /// - ``any(_:)``
    /// - ``all(_:)``
    /// - ``none``
    /// - ``true``
    /// - ``false``
    /// - ``init(booleanLiteral:)``
    /// - ``hasResponse(taskId:)``
    /// - ``isMissingResponse(taskId:)``
    /// - ``responseValueComparison(taskId:operator:value:)``
    ///
    /// ### Supporting Types
    /// - ``ComparisonOperator``
    /// - ``Value``
    public indirect enum Condition: ExpressibleByBooleanLiteral, Sendable {
        /// A condition that is satisfied if `nested` is not satisfied.
        case not(_ nested: Condition)
        
        /// A condition that is satisfied if any of its contained conditions are satisfied..
        ///
        /// If there are no nested conditions, `any` evaluates to `false`.
        case any(Set<Condition>)
        
        /// A condition that is satisfied if all of its contained conditions are satisfied.
        ///
        /// If there are no nested conditions, `all` evaluates to `true`.
        case all(Set<Condition>)
        
        /// A condition that is satisfied if a response exists for the task at `taskPath`.
        ///
        /// This condition only checks whether a response exists; it does not take the task's optionality into account.
        /// (Use ``isMissingResponse(taskId:)`` instead if you need that.)
        ///
        /// - parameter taskId: The id of a task within the questionnaire.
        case hasResponse(taskId: Task.ID)
        
        /// A condition that is satisfied if a response is currently missing for the  task at `taskPath`.
        ///
        /// - Note: This is not the opposite of ``hasResponse(taskId:)``.
        ///     For an optional task that doesn't have a response, this would evaluate to `false` (because the task isn't required, the response isn't missing),
        ///     whereas ``hasResponse(taskId:)`` would also evaluate to `false`, since it only checks for the existence of a response.
        case isMissingResponse(taskId: Task.ID)
        
        /// A condition that compares a task's response to some value.
        ///
        /// - Note: Not all comparisons make sense for all question types.
        ///     If a response is compared against a value of a different type, or if the operator isn't applicable for the type, the condition evaluates to `false`.
        ///
        /// - parameter taskId: The id of the task whose response should be inspected.
        /// - parameter operator: The comparison operation
        /// - parameter value: The value against which the task's response should be compared
        case responseValueComparison(taskId: Task.ID, operator: ComparisonOperator, value: Value)

        /// A condition evaluated by the questionnaire's ``QuestionnaireExpressionEngine``
        /// (SDC `enableWhenExpression`); disabled when no engine is available or the
        /// expression evaluates to empty or fails.
        case expression(String)
        
        
        /// Models https://hl7.org/fhir/valueset-questionnaire-enable-operator.html
        ///
        /// - Note: This enum intentionally does not implement the `exists` operation.
        ///     Use ``Questionnaire/Condition/hasResponse(taskId:)`` instead.
        public enum ComparisonOperator: Hashable, Sendable {
            /// True if at least one answer has a value that is equal to the enableWhen answer
            case equal
            /// True if at least one answer has a value that is not equal to the enableWhen answer.
            ///
            /// Unlike `.not(.responseValueComparison(…, .equal, …))`, this evaluates to `false`
            /// when the referenced question has no answer, matching FHIR's enableWhen semantics.
            case notEqual
            /// True if at least one answer has a value that is less than the enableWhen answer
            case lessThan
            /// True if at least one answer has a value that is greater than the enableWhen answer
            case greaterThan
            /// True if at least one answer has a value that is less or equal to the enableWhen answer
            case lessThanOrEqual
            /// True if at least one answer has a value that is greater or equal to the enableWhen answer
            case greaterThanOrEqual
        }

        /// Value used in comparison conditions.
        public enum Value: Hashable, Sendable {
            case bool(Bool)
            case integer(Int)
            case decimal(Double)
            case string(String)
            case date(DateComponents)
            /// A quantity, compared against numeric responses whose unit matches `unitCode`
            /// (a `nil` `unitCode` matches any unit).
            case quantity(value: Double, unitCode: String?)
            /// A choice option, identified by its ``Questionnaire/Task/Kind-swift.struct/ChoiceConfig/Option/id``.
            ///
            /// For options created from FHIR codings, the id is the `system|code` token
            /// (or the bare code when the coding has no system), so matching honors the
            /// coding's system per FHIR enableWhen semantics.
            case SCMCOption(id: String)
        }
        
        /// The lack of a condition.
        ///
        /// Always evaluates to `true`.
        public static var none: Self {
            true
        }
        
        /// A `Condition` that is always true.
        public static var `true`: Self {
            true
        }
        
        /// A `Condition` that is always false.
        public static var `false`: Self {
            false
        }
        
        /// Creates a ``Condition`` that always evaluates to the specified boolean value.
        public init(booleanLiteral value: Bool) {
            self = value ? .all([]) : .any([])
        }
        
        /// Constructs a condition that is true iff two other conditions are true.
        public static func && (lhs: Self, rhs: Self) -> Self {
            .all([lhs, rhs])
        }
        
        /// Constructs a condition that is true iff either of other conditions is true.
        public static func || (lhs: Self, rhs: Self) -> Self {
            .any([lhs, rhs])
        }
        
        /// Negates a condition
        public static prefix func ! (rhs: Self) -> Self {
            .not(rhs)
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire.Condition: Hashable {
    /// Determines whether two conditions are semantically equivalent.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.simplified().isEqual(to: rhs.simplified())
    }
    
    private func isEqual(to other: Self) -> Bool {
        switch (self, other) {
        case let (.not(lhs), .not(rhs)):
            lhs.isEqual(to: rhs)
        case let (.any(lhs), .any(rhs)):
            Set(lhs) == Set(rhs)
        case let (.all(lhs), .all(rhs)):
            Set(lhs) == Set(rhs)
        case let (.hasResponse(lhs), .hasResponse(rhs)):
            lhs == rhs
        case let (.isMissingResponse(lhs), .isMissingResponse(rhs)):
            lhs == rhs
        case let (.responseValueComparison(lhsTask, lhsOp, lhsVal), .responseValueComparison(rhsTask, rhsOp, rhsVal)):
            lhsTask == rhsTask && lhsOp == rhsOp && lhsVal == rhsVal
        case let (.expression(lhs), .expression(rhs)):
            lhs == rhs
        default:
            false
        }
    }
    
    public func hash(into hasher: inout Hasher) {
        switch simplified() {
        case .not(let inner):
            hasher.combine(0)
            hasher.combine(inner)
        case .any(let inner):
            hasher.combine(1)
            hasher.combine(inner)
        case .all(let inner):
            hasher.combine(2)
            hasher.combine(inner)
        case .hasResponse(let taskId):
            hasher.combine(3)
            hasher.combine(taskId)
        case .isMissingResponse(let taskId):
            hasher.combine(4)
            hasher.combine(taskId)
        case let .responseValueComparison(taskId, `operator`, value):
            hasher.combine(5)
            hasher.combine(taskId)
            hasher.combine(`operator`)
            hasher.combine(value)
        case .expression(let expression):
            hasher.combine(6)
            hasher.combine(expression)
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire.Condition {
    private static func simplifiedNegation(of condition: Self) -> Self {
        switch condition {
        case .not(let inner):
            inner
        case true:
            false
        case false:
            true
        default:
            .not(condition)
        }
    }

    private static func simplifiedDisjunction(of conditions: Set<Self>) -> Self {
        let conditions: Set<Self> = conditions.compactMapIntoSet {
            switch $0.simplified() {
            case false: nil
            case let cond: cond
            }
        }
        if conditions.isEmpty {
            return false
        } else if conditions.contains(true) {
            return true
        } else {
            return .any(conditions)
        }
    }

    private static func simplifiedConjunction(of conditions: Set<Self>) -> Self {
        let conditions: Set<Self> = conditions.compactMapIntoSet {
            switch $0.simplified() {
            case true: nil
            case let cond: cond
            }
        }
        if conditions.isEmpty {
            return true
        } else if conditions.contains(false) {
            return false
        } else {
            return .all(conditions)
        }
    }

    mutating func simplify() {
        self = self.simplified()
    }

    package func simplified() -> Self {
        switch self {
        case .not(let inner):
            Self.simplifiedNegation(of: inner.simplified())
        case .any(let inner):
            Self.simplifiedDisjunction(of: inner)
        case .all(let inner):
            Self.simplifiedConjunction(of: inner)
        case .hasResponse, .isMissingResponse, .responseValueComparison, .expression:
            self
        }
    }
}
