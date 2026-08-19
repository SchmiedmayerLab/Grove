//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// A result builder used to aggregate multiple ``LLMTool``s within the ``LLMOpenAISchema``.
@resultBuilder
@available(iOS 18, macOS 15, watchOS 11, *)
public enum LLMToolBuilder {
    /// If declared, provides contextual type information for statement expressions to translate them into partial results.
    public static func buildExpression<L: LLMTool>(_ expression: L) -> [L] {
        [expression]
    }

    /// Required by every result builder to build combined results from statement blocks.
    public static func buildBlock(_ children: [any LLMTool]...) -> [any LLMTool] {
        children.flatMap { $0 }
    }

    /// Enables support for `if` statements that do not have an `else`.
    public static func buildOptional(_ component: [any LLMTool]?) -> [any LLMTool] {
        // swiftlint:disable:previous discouraged_optional_collection
        // The optional collection is a requirement defined by @resultBuilder, we can not use a non-optional collection here.
        component ?? []
    }

    /// With buildEither(second:), enables support for 'if-else' and 'switch' statements by folding conditional results into a single result.
    public static func buildEither(first: [any LLMTool]) -> [any LLMTool] {
        first
    }

    /// With buildEither(first:), enables support for 'if-else' and 'switch' statements by folding conditional results into a single result.
    public static func buildEither(second: [any LLMTool]) -> [any LLMTool] {
        second
    }
    
    /// Enables support for 'for..in' loops by combining the results of all iterations into a single result.
    public static func buildArray(_ components: [[any LLMTool]]) -> [any LLMTool] {
        components.flatMap { $0 }
    }
    
    /// If declared, this will be called on the partial result of an 'if #available' block to allow the result builder to erase type information.
    public static func buildLimitedAvailability(_ component: [any LLMTool]) -> [any LLMTool] {
        component
    }
    
    /// If declared, this will be called on the partial result from the outermost block statement to produce the final returned result.
    public static func buildFinalResult(_ component: [any LLMTool]) -> _LLMToolCollection {
        _LLMToolCollection(functions: component)
    }
}
