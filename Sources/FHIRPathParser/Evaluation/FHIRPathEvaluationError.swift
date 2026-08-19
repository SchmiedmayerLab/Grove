//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// An error produced while evaluating a FHIRPath expression.
public enum FHIRPathEvaluationError: Error, CustomStringConvertible {
    /// The expression uses a function the evaluator does not implement.
    case unsupportedFunction(String)
    /// The expression uses an operator or language feature the evaluator does not implement.
    case unsupported(String)
    /// The expression is syntactically invalid.
    case syntaxError(String)
    /// The expression is structurally unusable (e.g. a missing subtree).
    case malformedExpression(String)
    /// An operation was applied to operands of incompatible types.
    case typeMismatch(String)
    /// A referenced environment variable or constant is not defined.
    case unknownConstant(String)
    /// The input data could not be prepared for evaluation.
    case malformedInput(String)

    public var description: String {
        switch self {
        case .unsupportedFunction(let name):
            "Unsupported FHIRPath function '\(name)()'"
        case .unsupported(let what):
            "Unsupported FHIRPath feature: \(what)"
        case .syntaxError(let message):
            "FHIRPath syntax error: \(message)"
        case .malformedExpression(let message):
            "Malformed FHIRPath expression: \(message)"
        case .typeMismatch(let message):
            "FHIRPath type mismatch: \(message)"
        case .unknownConstant(let name):
            "Unknown FHIRPath constant '%\(name)'"
        case .malformedInput(let message):
            "Malformed FHIRPath input: \(message)"
        }
    }
}
