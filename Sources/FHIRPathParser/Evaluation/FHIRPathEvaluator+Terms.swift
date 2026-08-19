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
    static func unquote(_ text: String) -> String {
        var result = text
        if (result.hasPrefix("'") && result.hasSuffix("'") && result.count >= 2)
            || (result.hasPrefix("`") && result.hasSuffix("`") && result.count >= 2)
            || (result.hasPrefix("\"") && result.hasSuffix("\"") && result.count >= 2) {
            result = String(result.dropFirst().dropLast())
        }
        guard result.contains("\\") else {
            return result
        }
        // Scanned in one pass so that an escaped backslash cannot be re-read as the start of an escape.
        var unescaped = ""
        var characters = result.makeIterator()
        while let character = characters.next() {
            guard character == "\\", let escaped = characters.next() else {
                unescaped.append(character)
                continue
            }
            switch escaped {
            case "'", "\"", "`", "/", "\\":
                unescaped.append(escaped)
            case "r":
                unescaped.append("\r")
            case "n":
                unescaped.append("\n")
            case "t":
                unescaped.append("\t")
            case "f":
                unescaped.append("\u{0C}")
            default:
                unescaped.append(character)
                unescaped.append(escaped)
            }
        }
        return unescaped
    }

    private static func number(from text: String) -> FHIRPathValue {
        if !text.contains("."), let integer = Int(text) {
            return .integer(integer)
        }
        return .decimal(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? 0)
    }

    private static func quantity(from ctx: FHIRPathParser.QuantityLiteralContext) throws -> FHIRPathValue {
        guard let quantity = ctx.quantity(), let numberText = quantity.NUMBER()?.getText() else {
            throw FHIRPathEvaluationError.malformedExpression("invalid quantity literal")
        }
        guard let value = Decimal(string: numberText, locale: Locale(identifier: "en_US_POSIX")) else {
            throw FHIRPathEvaluationError.malformedExpression("invalid quantity value '\(numberText)'")
        }
        return .quantity(value: value, unit: Self.unquote(quantity.unit()?.getText() ?? "1"))
    }

    func evaluate(term ctx: FHIRPathParser.TermContext, focus: [FHIRPathValue]) throws -> [FHIRPathValue] {
        switch ctx {
        case let ctx as FHIRPathParser.LiteralTermContext:
            guard let literal = ctx.literal() else {
                throw FHIRPathEvaluationError.malformedExpression("literal term without literal")
            }
            return try evaluate(literal: literal)
        case let ctx as FHIRPathParser.InvocationTermContext:
            guard let invocation = ctx.invocation() else {
                throw FHIRPathEvaluationError.malformedExpression("invocation term without invocation")
            }
            return try evaluate(invocation: invocation, input: focus, focus: focus, isRootTerm: true)
        case let ctx as FHIRPathParser.ExternalConstantTermContext:
            guard let constant = ctx.externalConstant() else {
                throw FHIRPathEvaluationError.malformedExpression("constant term without constant")
            }
            var name = constant.identifier()?.getText() ?? constant.STRING()?.getText() ?? ""
            name = Self.unquote(name)
            guard let values = context.constants[name] else {
                throw FHIRPathEvaluationError.unknownConstant(name)
            }
            return values
        case let ctx as FHIRPathParser.ParenthesizedTermContext:
            guard let inner = ctx.expression() else {
                throw FHIRPathEvaluationError.malformedExpression("empty parentheses")
            }
            return try evaluate(inner, focus: focus)
        default:
            throw FHIRPathEvaluationError.unsupported("term '\(ctx.getText())'")
        }
    }

    private func evaluate(literal ctx: FHIRPathParser.LiteralContext) throws -> [FHIRPathValue] {
        switch ctx {
        case is FHIRPathParser.NullLiteralContext:
            return []
        case let ctx as FHIRPathParser.BooleanLiteralContext:
            return [.boolean(ctx.getText() == "true")]
        case let ctx as FHIRPathParser.StringLiteralContext:
            return [.string(Self.unquote(ctx.getText()))]
        case let ctx as FHIRPathParser.NumberLiteralContext:
            return [Self.number(from: ctx.getText())]
        case let ctx as FHIRPathParser.DateTimeLiteralContext:
            guard let value = FHIRPathValue.parseTemporal(ctx.getText()) else {
                throw FHIRPathEvaluationError.malformedExpression("invalid date literal '\(ctx.getText())'")
            }
            return [value]
        case let ctx as FHIRPathParser.TimeLiteralContext:
            guard let value = FHIRPathValue.parseTemporal(ctx.getText()) else {
                throw FHIRPathEvaluationError.malformedExpression("invalid time literal '\(ctx.getText())'")
            }
            return [value]
        case let ctx as FHIRPathParser.QuantityLiteralContext:
            return try [Self.quantity(from: ctx)]
        default:
            throw FHIRPathEvaluationError.unsupported("literal '\(ctx.getText())'")
        }
    }
}
