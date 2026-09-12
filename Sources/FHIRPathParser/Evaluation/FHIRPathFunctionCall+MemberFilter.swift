//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Antlr4


/// The `where` criteria a form asks most: a member against a string, or several such comparisons on one member
/// joined by `or`, which is how SDC reaches an item (`descendants().where(linkId = 'x')`) or an answer
/// (`value.where(code = 'yes' or code = 'no')`).
///
/// Answered from the member itself rather than by evaluating the criteria on every element: over a whole
/// response that is thousands of evaluations per expression, and what they would find is the same.
struct MemberFilter {
    let member: String
    let literals: Set<String>

    init?(criteria: FHIRPathParser.ExpressionContext) {
        guard let (member, literals) = Self.comparison(in: criteria) else {
            return nil
        }
        self.member = member
        self.literals = literals
    }

    private static func comparison(in ctx: FHIRPathParser.ExpressionContext) -> (String, Set<String>)? {
        switch ctx {
        case let ctx as FHIRPathParser.OrExpressionContext:
            guard ctx.operatorText == "or", let lhs = ctx.expression(0), let rhs = ctx.expression(1),
                  let left = comparison(in: lhs), let right = comparison(in: rhs), left.0 == right.0 else {
                return nil
            }
            return (left.0, left.1.union(right.1))
        case let ctx as FHIRPathParser.EqualityExpressionContext:
            guard ctx.operatorText == "=", let lhs = ctx.expression(0), let rhs = ctx.expression(1),
                  let member = memberName(of: lhs), let literal = stringLiteral(of: rhs) else {
                return nil
            }
            return (member, [literal])
        case let ctx as FHIRPathParser.TermExpressionContext:
            guard let term = ctx.term() as? FHIRPathParser.ParenthesizedTermContext, let inner = term.expression() else {
                return nil
            }
            return comparison(in: inner)
        default:
            return nil
        }
    }

    /// A plain member of the element; a name starting uppercase would be read as a type filter instead.
    private static func memberName(of ctx: FHIRPathParser.ExpressionContext) -> String? {
        guard let term = (ctx as? FHIRPathParser.TermExpressionContext)?.term() as? FHIRPathParser.InvocationTermContext,
              let invocation = term.invocation() as? FHIRPathParser.MemberInvocationContext,
              let identifier = invocation.identifier()?.getText() else {
            return nil
        }
        let name = FHIRPathEvaluator.unquote(identifier)
        return name.first?.isUppercase == true ? nil : name
    }

    private static func stringLiteral(of ctx: FHIRPathParser.ExpressionContext) -> String? {
        guard let term = (ctx as? FHIRPathParser.TermExpressionContext)?.term() as? FHIRPathParser.LiteralTermContext,
              let literal = term.literal() as? FHIRPathParser.StringLiteralContext else {
            return nil
        }
        return FHIRPathEvaluator.unquote(literal.getText())
    }

    /// Whether an element has the member as a single string among the literals, which is when the criteria
    /// evaluate to `true` on it.
    func matches(_ value: FHIRPathValue) -> Bool {
        guard case .object(let node) = value else {
            return false
        }
        let children = node.children(named: member)
        guard children.count == 1, case .string(let string) = children[0] else {
            return false
        }
        return literals.contains(string)
    }
}
