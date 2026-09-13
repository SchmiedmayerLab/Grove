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
            if let cache = context.descendants {
                if let constant = cachedDescendants(lhs, invocation, in: cache) {
                    return try cache.descendants(of: constant) { try self.evaluate(lhs, invocation, focus: focus) }
                }
                if let filter = Self.memberFilter(of: invocation), let inner = lhs as? FHIRPathParser.InvocationExpressionContext,
                   let innerLhs = inner.expression(), let innerInvocation = inner.invocation(),
                   let constant = cachedDescendants(innerLhs, innerInvocation, in: cache) {
                    return try cache.descendants(of: constant, whose: filter.member, isAmong: filter.literals) {
                        try self.evaluate(innerLhs, innerInvocation, focus: focus)
                    }
                }
            }
            return try evaluate(lhs, invocation, focus: focus)
        case let ctx as FHIRPathParser.IndexerExpressionContext:
            return try evaluateIndexer(ctx, focus: focus)
        default:
            return try evaluateOperator(ctx, focus: focus)
        }
    }

    private func evaluate(
        _ lhs: FHIRPathParser.ExpressionContext,
        _ invocation: FHIRPathParser.InvocationContext,
        focus: [FHIRPathValue]
    ) throws -> [FHIRPathValue] {
        try evaluate(invocation: invocation, input: evaluate(lhs, focus: focus), focus: focus)
    }

    /// The constant whose kept descendants `lhs.invocation` reads, when that is what it does.
    private func cachedDescendants(
        _ lhs: FHIRPathParser.ExpressionContext,
        _ invocation: FHIRPathParser.InvocationContext,
        in cache: FHIRPathDescendantsCache
    ) -> String? {
        guard let constant = Self.constantName(of: lhs), cache.keeps(constant), Self.isDescendants(invocation) else {
            return nil
        }
        return constant
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


extension FHIRPathEvaluator {
    /// The `%name` a term reads, when it is one.
    fileprivate static func constantName(of ctx: FHIRPathParser.ExpressionContext) -> String? {
        guard let term = (ctx as? FHIRPathParser.TermExpressionContext)?.term() as? FHIRPathParser.ExternalConstantTermContext,
              let constant = term.externalConstant() else {
            return nil
        }
        return unquote(constant.identifier()?.getText() ?? constant.STRING()?.getText() ?? "")
    }

    /// Whether the invocation is a bare `descendants()`.
    fileprivate static func isDescendants(_ ctx: FHIRPathParser.InvocationContext) -> Bool {
        guard let function = (ctx as? FHIRPathParser.FunctionInvocationContext)?.function() else {
            return false
        }
        return function.identifier()?.getText() == "descendants" && (function.paramList()?.expression() ?? []).isEmpty
    }

    /// The filter of a `where(...)` invocation, when its criteria are a member against string literals.
    fileprivate static func memberFilter(of ctx: FHIRPathParser.InvocationContext) -> MemberFilter? {
        guard let function = (ctx as? FHIRPathParser.FunctionInvocationContext)?.function(),
              function.identifier()?.getText() == "where",
              let params = function.paramList()?.expression(), params.count == 1 else {
            return nil
        }
        return MemberFilter(criteria: params[0])
    }
}
