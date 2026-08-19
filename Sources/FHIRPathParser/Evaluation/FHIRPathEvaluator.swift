//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Antlr4


struct FHIRPathEvaluator {
    let context: FHIRPathEvaluationContext
    /// The `$index` within the innermost iteration function, if any.
    var iterationIndex: Int?

    func evaluate(_ ctx: FHIRPathParser.ExpressionContext, focus: [FHIRPathValue]) throws -> [FHIRPathValue] {
        switch ctx {
        case let ctx as FHIRPathParser.TermExpressionContext:
            guard let term = ctx.term() else {
                throw FHIRPathEvaluationError.malformedExpression("term expression without term")
            }
            return try evaluate(term: term, focus: focus)
        case let ctx as FHIRPathParser.InvocationExpressionContext:
            guard let lhs = ctx.expression(), let invocation = ctx.invocation() else {
                throw FHIRPathEvaluationError.malformedExpression("invocation expression without operands")
            }
            let input = try evaluate(lhs, focus: focus)
            return try evaluate(invocation: invocation, input: input, focus: focus)
        case let ctx as FHIRPathParser.IndexerExpressionContext:
            return try evaluateIndexer(ctx, focus: focus)
        default:
            return try evaluateOperator(ctx, focus: focus)
        }
    }

    private func evaluateIndexer(_ ctx: FHIRPathParser.IndexerExpressionContext, focus: [FHIRPathValue]) throws -> [FHIRPathValue] {
        guard let lhs = ctx.expression(0), let rhs = ctx.expression(1) else {
            throw FHIRPathEvaluationError.malformedExpression("indexer without operands")
        }
        let input = try evaluate(lhs, focus: focus)
        guard case .integer(let index)? = try evaluate(rhs, focus: focus).singleton else {
            return []
        }
        return input.indices.contains(index) ? [input[index]] : []
    }

    // MARK: Invocations

    func evaluate(
        invocation ctx: FHIRPathParser.InvocationContext,
        input: [FHIRPathValue],
        focus: [FHIRPathValue],
        isRootTerm: Bool = false
    ) throws -> [FHIRPathValue] {
        switch ctx {
        case let ctx as FHIRPathParser.MemberInvocationContext:
            guard let identifier = ctx.identifier()?.getText() else {
                throw FHIRPathEvaluationError.malformedExpression("member invocation without name")
            }
            return evaluate(member: Self.unquote(identifier), input: input, isRootTerm: isRootTerm)
        case let ctx as FHIRPathParser.FunctionInvocationContext:
            guard let function = ctx.function(), let identifier = function.identifier()?.getText() else {
                throw FHIRPathEvaluationError.malformedExpression("function invocation without name")
            }
            let call = FHIRPathFunctionCall(
                evaluator: self,
                name: Self.unquote(identifier),
                params: function.paramList()?.expression() ?? [],
                input: input,
                focus: focus
            )
            return try call.evaluate()
        case is FHIRPathParser.ThisInvocationContext:
            return focus
        case is FHIRPathParser.IndexInvocationContext:
            guard let iterationIndex else {
                throw FHIRPathEvaluationError.unsupported("$index outside of an iteration function")
            }
            return [.integer(iterationIndex)]
        case is FHIRPathParser.TotalInvocationContext:
            throw FHIRPathEvaluationError.unsupported("$total (aggregate() is not supported)")
        default:
            throw FHIRPathEvaluationError.unsupported("invocation '\(ctx.getText())'")
        }
    }

    private func evaluate(member name: String, input: [FHIRPathValue], isRootTerm: Bool) -> [FHIRPathValue] {
        // A leading type name (e.g. `QuestionnaireResponse.item`) filters by resourceType.
        if isRootTerm, name.first?.isUppercase == true {
            let matching = input.filter {
                if case .object(let node) = $0 { node.stringMember("resourceType") == name } else { false }
            }
            let anyResource = input.contains {
                if case .object(let node) = $0 { node.stringMember("resourceType") != nil } else { false }
            }
            if !matching.isEmpty || anyResource {
                return matching
            }
        }
        return input.flatMap { value -> [FHIRPathValue] in
            guard case .object(let node) = value else {
                return []
            }
            return node.children(named: name).map(FHIRPathValue.init(node:))
        }
    }
}
