//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Antlr4
import Foundation


extension FHIRPathEvaluator {
    func evaluateOperator(_ ctx: FHIRPathParser.ExpressionContext, focus: [FHIRPathValue]) throws -> [FHIRPathValue] {
        switch ctx {
        case let ctx as FHIRPathParser.PolarityExpressionContext:
            return try evaluatePolarity(ctx, focus: focus)
        case let ctx as FHIRPathParser.AdditiveExpressionContext:
            return try evaluateAdditive(ctx, focus: focus)
        case let ctx as FHIRPathParser.MultiplicativeExpressionContext:
            return try evaluateMultiplicative(ctx, focus: focus)
        case let ctx as FHIRPathParser.UnionExpressionContext:
            return try evaluateUnion(ctx, focus: focus)
        case let ctx as FHIRPathParser.InequalityExpressionContext:
            return try evaluateInequality(ctx, focus: focus)
        case let ctx as FHIRPathParser.EqualityExpressionContext:
            return try evaluateEquality(ctx, focus: focus)
        case let ctx as FHIRPathParser.MembershipExpressionContext:
            return try evaluateMembership(ctx, focus: focus)
        case let ctx as FHIRPathParser.TypeExpressionContext:
            return try evaluateType(ctx, focus: focus)
        default:
            return try evaluateLogical(ctx, focus: focus)
        }
    }

    private func evaluateLogical(_ ctx: FHIRPathParser.ExpressionContext, focus: [FHIRPathValue]) throws -> [FHIRPathValue] {
        switch ctx {
        case let ctx as FHIRPathParser.AndExpressionContext:
            return try evaluateAnd(ctx, focus: focus)
        case let ctx as FHIRPathParser.OrExpressionContext:
            return try evaluateOr(ctx, focus: focus)
        case let ctx as FHIRPathParser.ImpliesExpressionContext:
            return try evaluateImplies(ctx, focus: focus)
        default:
            throw FHIRPathEvaluationError.unsupported("expression form '\(ctx.getText())'")
        }
    }

    private func evaluatePolarity(_ ctx: FHIRPathParser.PolarityExpressionContext, focus: [FHIRPathValue]) throws -> [FHIRPathValue] {
        guard let expression = ctx.expression(), let operatorText = ctx.operatorText else {
            throw FHIRPathEvaluationError.malformedExpression("polarity without operand")
        }
        let value = try evaluate(expression, focus: focus)
        guard operatorText == "-" else {
            return value
        }
        switch try value.singleton {
        case nil:
            return []
        case .integer(let integer):
            return [.integer(-integer)]
        case .decimal(let decimal):
            return [.decimal(-decimal)]
        case let .quantity(quantity, unit):
            return [.quantity(value: -quantity, unit: unit)]
        case let value?:
            throw FHIRPathEvaluationError.typeMismatch("Cannot negate \(value)")
        }
    }

    private func evaluateAdditive(_ ctx: FHIRPathParser.AdditiveExpressionContext, focus: [FHIRPathValue]) throws -> [FHIRPathValue] {
        guard let lhs = ctx.expression(0), let rhs = ctx.expression(1), let operatorText = ctx.operatorText else {
            throw FHIRPathEvaluationError.malformedExpression("additive expression without operands")
        }
        let lhsValues = try evaluate(lhs, focus: focus)
        let rhsValues = try evaluate(rhs, focus: focus)
        if operatorText == "&" {
            let lhsString = try lhsValues.singleton?.stringValue ?? ""
            let rhsString = try rhsValues.singleton?.stringValue ?? ""
            return [.string(lhsString + rhsString)]
        }
        guard let lhsValue = try lhsValues.singleton, let rhsValue = try rhsValues.singleton else {
            return []
        }
        return try Self.applyAdditive(lhsValue, rhsValue, operatorText: operatorText)
    }

    private func evaluateMultiplicative(_ ctx: FHIRPathParser.MultiplicativeExpressionContext, focus: [FHIRPathValue]) throws -> [FHIRPathValue] {
        guard let lhs = ctx.expression(0), let rhs = ctx.expression(1), let operatorText = ctx.operatorText else {
            throw FHIRPathEvaluationError.malformedExpression("multiplicative expression without operands")
        }
        guard let lhsValue = try evaluate(lhs, focus: focus).singleton,
              let rhsValue = try evaluate(rhs, focus: focus).singleton else {
            return []
        }
        if case let (.integer(lhsInt), .integer(rhsInt)) = (lhsValue, rhsValue) {
            return try Self.applyMultiplicative(lhsInt, rhsInt, operatorText: operatorText)
        }
        guard let lhsDecimal = lhsValue.decimalValue, let rhsDecimal = rhsValue.decimalValue else {
            throw FHIRPathEvaluationError.typeMismatch("Cannot apply '\(operatorText)' to \(lhsValue) and \(rhsValue)")
        }
        return try Self.applyMultiplicative(lhsDecimal, rhsDecimal, operatorText: operatorText)
    }

    private func evaluateUnion(_ ctx: FHIRPathParser.UnionExpressionContext, focus: [FHIRPathValue]) throws -> [FHIRPathValue] {
        guard let lhs = ctx.expression(0), let rhs = ctx.expression(1) else {
            throw FHIRPathEvaluationError.malformedExpression("union without operands")
        }
        var result = try evaluate(lhs, focus: focus)
        for value in try evaluate(rhs, focus: focus) where !result.contains(value) {
            result.append(value)
        }
        return result
    }

    private func evaluateInequality(_ ctx: FHIRPathParser.InequalityExpressionContext, focus: [FHIRPathValue]) throws -> [FHIRPathValue] {
        guard let lhs = ctx.expression(0), let rhs = ctx.expression(1), let operatorText = ctx.operatorText else {
            throw FHIRPathEvaluationError.malformedExpression("comparison without operands")
        }
        guard let lhsValue = try evaluate(lhs, focus: focus).singleton,
              let rhsValue = try evaluate(rhs, focus: focus).singleton,
              let comparison = try lhsValue.fhirCompare(rhsValue) else {
            return []
        }
        let result: Bool
        switch operatorText {
        case "<":
            result = comparison == .orderedAscending
        case ">":
            result = comparison == .orderedDescending
        case "<=":
            result = comparison != .orderedDescending
        case ">=":
            result = comparison != .orderedAscending
        default:
            throw FHIRPathEvaluationError.unsupported("operator '\(operatorText)'")
        }
        return [.boolean(result)]
    }

    private func evaluateEquality(_ ctx: FHIRPathParser.EqualityExpressionContext, focus: [FHIRPathValue]) throws -> [FHIRPathValue] {
        guard let lhs = ctx.expression(0), let rhs = ctx.expression(1), let operatorText = ctx.operatorText else {
            throw FHIRPathEvaluationError.malformedExpression("equality without operands")
        }
        let lhsValues = try evaluate(lhs, focus: focus)
        let rhsValues = try evaluate(rhs, focus: focus)
        if lhsValues.isEmpty || rhsValues.isEmpty {
            guard operatorText == "~" || operatorText == "!~" else {
                return []
            }
            let result = lhsValues.isEmpty && rhsValues.isEmpty
            return [.boolean(operatorText == "~" ? result : !result)]
        }
        return try Self.applyEquality(lhsValues, rhsValues, operatorText: operatorText)
    }

    private func evaluateMembership(_ ctx: FHIRPathParser.MembershipExpressionContext, focus: [FHIRPathValue]) throws -> [FHIRPathValue] {
        guard let lhs = ctx.expression(0), let rhs = ctx.expression(1), let operatorText = ctx.operatorText else {
            throw FHIRPathEvaluationError.malformedExpression("membership without operands")
        }
        let lhsValues = try evaluate(lhs, focus: focus)
        let rhsValues = try evaluate(rhs, focus: focus)
        let (needles, haystack) = operatorText == "in" ? (lhsValues, rhsValues) : (rhsValues, lhsValues)
        if needles.isEmpty {
            return operatorText == "in" ? [] : [.boolean(false)]
        }
        return [.boolean(needles.allSatisfy { needle in haystack.contains { $0.fhirEquals(needle) == .true } })]
    }

    private func evaluateAnd(_ ctx: FHIRPathParser.AndExpressionContext, focus: [FHIRPathValue]) throws -> [FHIRPathValue] {
        guard let lhs = ctx.expression(0), let rhs = ctx.expression(1) else {
            throw FHIRPathEvaluationError.malformedExpression("and without operands")
        }
        let lhsValue = try Self.singletonBoolean(of: try evaluate(lhs, focus: focus))
        let rhsValue = try Self.singletonBoolean(of: try evaluate(rhs, focus: focus))
        switch (lhsValue, rhsValue) {
        case (.false, _), (_, .false):
            return [.boolean(false)]
        case (.true, .true):
            return [.boolean(true)]
        default:
            return []
        }
    }

    private func evaluateOr(_ ctx: FHIRPathParser.OrExpressionContext, focus: [FHIRPathValue]) throws -> [FHIRPathValue] {
        guard let lhs = ctx.expression(0), let rhs = ctx.expression(1), let operatorText = ctx.operatorText else {
            throw FHIRPathEvaluationError.malformedExpression("or without operands")
        }
        let lhsValue = try Self.singletonBoolean(of: try evaluate(lhs, focus: focus))
        let rhsValue = try Self.singletonBoolean(of: try evaluate(rhs, focus: focus))
        if operatorText == "xor" {
            guard lhsValue != .empty, rhsValue != .empty else {
                return []
            }
            return [.boolean(lhsValue != rhsValue)]
        }
        switch (lhsValue, rhsValue) {
        case (.true, _), (_, .true):
            return [.boolean(true)]
        case (.false, .false):
            return [.boolean(false)]
        default:
            return []
        }
    }

    private func evaluateImplies(_ ctx: FHIRPathParser.ImpliesExpressionContext, focus: [FHIRPathValue]) throws -> [FHIRPathValue] {
        guard let lhs = ctx.expression(0), let rhs = ctx.expression(1) else {
            throw FHIRPathEvaluationError.malformedExpression("implies without operands")
        }
        let lhsValue = try Self.singletonBoolean(of: try evaluate(lhs, focus: focus))
        let rhsValue = try Self.singletonBoolean(of: try evaluate(rhs, focus: focus))
        switch (lhsValue, rhsValue) {
        case (.false, _), (.true, .true), (.empty, .true):
            return [.boolean(true)]
        case (.true, .false):
            return [.boolean(false)]
        default:
            return []
        }
    }

    private func evaluateType(_ ctx: FHIRPathParser.TypeExpressionContext, focus: [FHIRPathValue]) throws -> [FHIRPathValue] {
        guard let expression = ctx.expression(), let typeSpecifier = ctx.typeSpecifier()?.getText(), let operatorText = ctx.operatorText else {
            throw FHIRPathEvaluationError.malformedExpression("type expression without operands")
        }
        let values = try evaluate(expression, focus: focus)
        switch operatorText {
        case "is":
            guard let value = try values.singleton else {
                return []
            }
            return [.boolean(try Self.matchesType(value, name: typeSpecifier))]
        case "as":
            return try values.filter { try Self.matchesType($0, name: typeSpecifier) }
        default:
            throw FHIRPathEvaluationError.unsupported("operator '\(operatorText)'")
        }
    }
}


// MARK: Operand Arithmetic

extension FHIRPathEvaluator {
    private static func applyAdditive(_ lhs: FHIRPathValue, _ rhs: FHIRPathValue, operatorText: String) throws -> [FHIRPathValue] {
        switch (lhs, rhs) {
        case let (.string(lhsString), .string(rhsString)) where operatorText == "+":
            return [.string(lhsString + rhsString)]
        case let (.integer(lhsInt), .integer(rhsInt)):
            return [.integer(operatorText == "+" ? lhsInt + rhsInt : lhsInt - rhsInt)]
        case (.date, _), (.dateTime, _), (.time, _):
            guard case let .quantity(amount, unit) = rhs else {
                throw FHIRPathEvaluationError.typeMismatch("Cannot apply '\(operatorText)' to \(lhs) and \(rhs)")
            }
            return try [Self.addCalendarQuantity(to: lhs, amount: operatorText == "+" ? amount : -amount, unit: unit)]
        case let (.quantity(lhsQuantity, lhsUnit), .quantity(rhsQuantity, rhsUnit)):
            guard lhsUnit == rhsUnit else {
                return []
            }
            return [.quantity(value: operatorText == "+" ? lhsQuantity + rhsQuantity : lhsQuantity - rhsQuantity, unit: lhsUnit)]
        default:
            guard let lhsDecimal = lhs.decimalValue, let rhsDecimal = rhs.decimalValue else {
                throw FHIRPathEvaluationError.typeMismatch("Cannot apply '\(operatorText)' to \(lhs) and \(rhs)")
            }
            return [.decimal(operatorText == "+" ? lhsDecimal + rhsDecimal : lhsDecimal - rhsDecimal)]
        }
    }

    private static func applyMultiplicative(_ lhs: Int, _ rhs: Int, operatorText: String) throws -> [FHIRPathValue] {
        switch operatorText {
        case "*":
            return [.integer(lhs * rhs)]
        case "div":
            return rhs == 0 ? [] : [.integer(lhs / rhs)]
        case "mod":
            return rhs == 0 ? [] : [.integer(lhs % rhs)]
        case "/":
            return rhs == 0 ? [] : [.decimal(Decimal(lhs) / Decimal(rhs))]
        default:
            throw FHIRPathEvaluationError.unsupported("operator '\(operatorText)'")
        }
    }

    private static func applyMultiplicative(_ lhs: Decimal, _ rhs: Decimal, operatorText: String) throws -> [FHIRPathValue] {
        switch operatorText {
        case "*":
            return [.decimal(lhs * rhs)]
        case "/":
            return rhs == 0 ? [] : [.decimal(lhs / rhs)]
        case "div":
            return rhs == 0 ? [] : [.decimal(Self.truncatedQuotient(of: lhs, by: rhs))]
        case "mod":
            return rhs == 0 ? [] : [.decimal(lhs - Self.truncatedQuotient(of: lhs, by: rhs) * rhs)]
        default:
            throw FHIRPathEvaluationError.unsupported("operator '\(operatorText)'")
        }
    }

    /// The quotient truncated toward zero, as FHIRPath's `div` and `mod` define them.
    private static func truncatedQuotient(of lhs: Decimal, by rhs: Decimal) -> Decimal {
        var quotient = lhs / rhs
        var truncated = Decimal()
        NSDecimalRound(&truncated, &quotient, 0, quotient < 0 ? .up : .down)
        return truncated
    }

    /// Compares two non-empty collections pairwise; `~` and `!~` compare strings case-insensitively.
    private static func applyEquality(
        _ lhsValues: [FHIRPathValue],
        _ rhsValues: [FHIRPathValue],
        operatorText: String
    ) throws -> [FHIRPathValue] {
        let equivalence = operatorText == "~" || operatorText == "!~"
        var allEqual = lhsValues.count == rhsValues.count
        if allEqual {
            for (lhsValue, rhsValue) in zip(lhsValues, rhsValues) {
                let equal: FHIRPathBoolean
                if equivalence, case let (.string(lhsString), .string(rhsString)) = (lhsValue, rhsValue) {
                    equal = FHIRPathBoolean(lhsString.lowercased() == rhsString.lowercased())
                } else {
                    equal = lhsValue.fhirEquals(rhsValue)
                }
                if equal == .empty {
                    return equivalence ? [.boolean(operatorText != "~")] : []
                }
                if equal == .false {
                    allEqual = false
                    break
                }
            }
        }
        switch operatorText {
        case "=", "~":
            return [.boolean(allEqual)]
        case "!=", "!~":
            return [.boolean(!allEqual)]
        default:
            throw FHIRPathEvaluationError.unsupported("operator '\(operatorText)'")
        }
    }
}


extension ParserRuleContext {
    /// The first terminal (operator) token's text, e.g. `+` in an additive expression.
    fileprivate var operatorText: String? {
        guard let children else {
            return nil
        }
        for child in children {
            if let node = child as? TerminalNode {
                return node.getText()
            }
        }
        return nil
    }
}
