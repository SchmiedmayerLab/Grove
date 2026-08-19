//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Antlr4
import Foundation


private final class SyntaxErrorCollector: BaseErrorListener {
    private(set) var firstMessage: String?

    override func syntaxError<T>(
        _ recognizer: Recognizer<T>,
        _ offendingSymbol: AnyObject?,
        _ line: Int,
        _ charPositionInLine: Int,
        _ msg: String,
        _ exception: AnyObject?
    ) {
        if firstMessage == nil {
            firstMessage = "line \(line):\(charPositionInLine) \(msg)"
        }
    }
}


/// Serializes all ANTLR parsing: the generated parser's shared ATN/DFA caches are
/// mutated during parsing and are not thread-safe, so concurrent parses crash.
private let fhirPathParsingLock = NSLock()


/// A parsed FHIRPath expression, ready for repeated evaluation.
///
/// Retains the lexer and token stream alongside the parse tree: ANTLR tokens hold
/// only weak references to their source stream and read their text lazily, so a
/// bare tree would lose its token text once the parsing locals deallocate.
public final class ParsedFHIRPathExpression {
    let tree: FHIRPathParser.ExpressionContext
    // periphery:ignore - strong lifetime anchor for ANTLR's weakly referenced token sources
    private let retainedSources: [AnyObject]

    fileprivate init(tree: FHIRPathParser.ExpressionContext, retainedSources: [AnyObject]) {
        self.tree = tree
        self.retainedSources = retainedSources
    }

    /// Evaluates the expression against the given context.
    public func evaluate(context: FHIRPathEvaluationContext) throws -> [FHIRPathValue] {
        try FHIRPathEvaluator(context: context).evaluate(tree, focus: context.focus)
    }

    /// Evaluates the expression and applies FHIRPath singleton boolean conversion:
    /// ``FHIRPathBoolean/empty`` for empty, the value for a boolean singleton,
    /// ``FHIRPathBoolean/true`` for any other singleton.
    public func evaluateBoolean(context: FHIRPathEvaluationContext) throws -> FHIRPathBoolean {
        try FHIRPathEvaluator.singletonBoolean(of: evaluate(context: context))
    }
}


extension FHIRPathExpression {
    /// Parses a FHIRPath expression, throwing on syntax errors.
    public static func parse(_ expression: String) throws -> ParsedFHIRPathExpression {
        fhirPathParsingLock.lock()
        defer {
            fhirPathParsingLock.unlock()
        }
        let stream = ANTLRInputStream(expression)
        let lexer = FHIRPathLexer(stream)
        let errors = SyntaxErrorCollector()
        lexer.removeErrorListeners()
        lexer.addErrorListener(errors)
        let tokenStream = CommonTokenStream(lexer)
        let parser = try FHIRPathParser(tokenStream)
        parser.removeErrorListeners()
        parser.addErrorListener(errors)
        let tree = try parser.expression()
        if let message = errors.firstMessage {
            throw FHIRPathEvaluationError.syntaxError(message)
        }
        return ParsedFHIRPathExpression(tree: tree, retainedSources: [stream, lexer, tokenStream, parser])
    }

    /// Evaluates a FHIRPath expression against the given context.
    ///
    /// The supported surface is the subset required by SDC questionnaires
    /// (paths, comparisons, arithmetic, boolean logic, and the common collection,
    /// string, math, and aggregate functions, plus SDC's `weight()`); anything
    /// outside it throws rather than mis-evaluating.
    public static func evaluate(expression: String, context: FHIRPathEvaluationContext) throws -> [FHIRPathValue] {
        try parse(expression).evaluate(context: context)
    }

    /// Evaluates an expression and applies FHIRPath singleton boolean conversion:
    /// ``FHIRPathBoolean/empty`` for empty, the value for a boolean singleton,
    /// ``FHIRPathBoolean/true`` for any other singleton.
    public static func evaluateBoolean(expression: String, context: FHIRPathEvaluationContext) throws -> FHIRPathBoolean {
        try parse(expression).evaluateBoolean(context: context)
    }
}
