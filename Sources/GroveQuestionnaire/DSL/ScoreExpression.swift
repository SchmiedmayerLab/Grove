//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


// MARK: Scored Options

/// An option scale whose cases carry scoring weights (FHIR `itemWeight`).
///
/// ``QuestionnaireOption/weight`` is optional, so a scale that forgot its weights scores
/// zero without complaint. Conforming to `ScoredOption` instead makes the weight a
/// requirement, and only questions over a `ScoredOption` can feed a ``ScoreExpression``.
///
/// ```swift
/// enum Frequency: String, ScoredOption {
///     case notAtAll = "not-at-all"
///     case nearlyEveryDay = "nearly-every-day"
///
///     var score: Decimal {
///         switch self {
///         case .notAtAll: 0
///         case .nearlyEveryDay: 3
///         }
///     }
/// }
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol ScoredOption: QuestionnaireOption {
    /// The case's scoring weight.
    var score: Decimal { get }
}


/// A question whose answers carry weights, so it can feed a computed score.
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol ScoredQuestion: TypedQuestion {}


// MARK: Score Expressions

/// A value that compiles down to an SDC FHIRPath expression.
///
/// Scores take the questions themselves rather than naming them in a string, so deleting a
/// question breaks the score at compile time instead of silently zeroing it.
///
/// ```swift
/// static let total = NumberQuestion("total", "Score")
///     .calculated(.sumOfWeights(of: interest, mood))
///     .readOnly()
///     .hidden()
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
public struct ScoreExpression: Hashable, Sendable {
    /// Sums the weights of every scored answer in the questionnaire.
    public static let sumOfAllWeights = Self("%resource.descendants().valueCoding.weight().sum()")

    let fhirPath: String

    private init(_ fhirPath: String) {
        self.fhirPath = fhirPath
    }

    /// Sums the weights of the answers to the given questions.
    public static func sumOfWeights(of first: any ScoredQuestion, _ rest: any ScoredQuestion...) -> Self {
        Self("%resource.descendants().\(whereLinkId(in: [first] + rest)).answer.valueCoding.weight().sum()")
    }

    /// Counts how many of the given questions have an answer.
    public static func countAnswered(of first: any TypedQuestion, _ rest: any TypedQuestion...) -> Self {
        Self("%resource.descendants().\(whereLinkId(in: [first] + rest)).answer.count()")
    }

    /// A literal value.
    public static func constant(_ value: Decimal) -> Self {
        Self("\(value)")
    }

    /// A hand-written FHIRPath expression.
    ///
    /// Checked for syntax at build time inside an ``Instrument()`` type, and unchecked
    /// everywhere else.
    public static func raw(_ fhirPath: String) -> Self {
        Self(fhirPath)
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        combine(lhs, "+", rhs)
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        combine(lhs, "-", rhs)
    }

    public static func * (lhs: Self, rhs: Self) -> Self {
        combine(lhs, "*", rhs)
    }

    public static func / (lhs: Self, rhs: Self) -> Self {
        combine(lhs, "/", rhs)
    }

    private static func combine(_ lhs: Self, _ operator: String, _ rhs: Self) -> Self {
        Self("(\(lhs.fhirPath)) \(`operator`) (\(rhs.fhirPath))")
    }

    private static func whereLinkId(in questions: [any TypedQuestion]) -> String {
        let terms = questions.map { "linkId='\($0.id.replacingOccurrences(of: "'", with: #"\'"#))'" }
        return "where(\(terms.joined(separator: " or ")))"
    }
}


// MARK: Conformances

@available(iOS 18, macOS 15, watchOS 11, *)
extension ScoredOption {
    /// The FHIR `itemWeight` exported for the case, which is always its ``score``.
    public var weight: Decimal? {
        score
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ChoiceQuestion: ScoredQuestion where Option: ScoredOption {}

@available(iOS 18, macOS 15, watchOS 11, *)
extension MultiChoiceQuestion: ScoredQuestion where Option: ScoredOption {}
