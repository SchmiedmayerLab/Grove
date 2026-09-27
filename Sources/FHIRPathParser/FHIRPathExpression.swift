//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Antlr4
import Foundation


/// A type can be evaluated from a FHIRPath expression.
public protocol _FHIRPathValue { // swiftlint:disable:this type_name
    /// Evaluate the expression for the given type
    ///
    /// The clock is an input rather than a read of the device so that every clock-sensitive expression in one
    /// form agrees: a questionnaire whose `minValue` is `today()` and whose `maxValue` is `today() + 3 months`
    /// must not straddle midnight between the two evaluations, and a replay reads the same day on any device.
    /// Callers normally use ``FHIRPathExpression/evaluate(expression:clock:as:)``.
    ///
    /// - Parameter expression: The expression to evalaute.
    /// - Parameter clock: The instant and zone `now()`, `today()` and `timeOfDay()` read.
    /// - Returns: The resulting value
    /// - Throws: Domain-specific error if the evaluation failed. Should use ``ExpressionError``.
    static func evaluate(
        _ expression: FHIRPathParser.ExpressionContext,
        clock: FHIRPathClock
    ) throws -> Self
}


/// Evaluate FHIRPath expressions.
public enum FHIRPathExpression {
    /// Evaluate a FHIRPath expression.
    ///
    /// For more information refer to [FHIRPath](https://hl7.org/fhirpath/).
    ///
    /// Below is a short code example on how to evaluate a Date expression:
    /// ```swift
    /// let date: Date = try FHIRPathExpression.evaluate(
    ///     expression: "today() + 3 months",
    ///     clock: FHIRPathClock(instant: authored, timeZone: participantZone)
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - expression: The FHIRPath expression to evaluate.
    ///   - clock: The instant and zone `now()`, `today()` and `timeOfDay()` read.
    ///   - value: The Swift Type the expression should be evalauted to.
    /// - Returns: The evalauted value.
    /// - Throws: Throws an error of ``ExpressionError`` if evaluation failed. Throws a respective parser error if the
    ///     provided expression doesn't follow the FHIRPath grammar.
    public static func evaluate<Value: _FHIRPathValue>(
        expression: String,
        clock: FHIRPathClock,
        as value: Value.Type = Value.self
    ) throws -> Value {
        // Routed through the locked parse: ANTLR's shared caches are not thread-safe.
        let parsed = try Self.parse(expression)
        return try value.evaluate(parsed.tree, clock: clock)
    }
}
