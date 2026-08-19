//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SwiftSyntax


/// A reference to a declaration, either bare (`mood`) or qualified (`Self.mood`, `GAD7.worry`).
struct InstrumentReference {
    let qualifier: String?
    let name: String
    let node: ExprSyntax
}


/// Collects the arguments of every `.enabledWhen(…)` in a syntax tree.
final class ConditionCollector: SyntaxVisitor {
    private(set) var conditions: [ExprSyntax] = []

    static func conditions(in syntax: some SyntaxProtocol) -> [ExprSyntax] {
        let collector = ConditionCollector(viewMode: .sourceAccurate)
        collector.walk(syntax)
        return collector.conditions
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let member = node.calledExpression.as(MemberAccessExprSyntax.self),
           member.declName.baseName.text == "enabledWhen" {
            conditions.append(contentsOf: node.arguments.map(\.expression))
        }
        return .visitChildren
    }
}


/// Collects the string literals that reach the FHIRPath engine unchanged: `.raw(…)`
/// expressions and `.constraint(…)` rules.
final class ExpressionLiteralCollector: SyntaxVisitor {
    private(set) var literals: [ExprSyntax] = []

    static func literals(in syntax: some SyntaxProtocol) -> [ExprSyntax] {
        let collector = ExpressionLiteralCollector(viewMode: .sourceAccurate)
        collector.walk(syntax)
        return collector.literals
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self) else {
            return .visitChildren
        }
        let baseName = member.base.flatMap { InstrumentSyntax.dottedName(of: $0).last }
        let isRaw = member.declName.baseName.text == "raw" && (member.base == nil || baseName == "ScoreExpression")
        let isConstraint = member.declName.baseName.text == "constraint" && member.base != nil
        if isRaw || isConstraint, let first = node.arguments.first, first.label == nil,
           first.expression.is(StringLiteralExprSyntax.self) {
            literals.append(first.expression)
        }
        return .visitChildren
    }
}


enum FHIRPathReferences {
    private static let pattern = try? NSRegularExpression(pattern: #"linkId\s*(?:=|!=)\s*'([^']*)'"#)

    /// The linkIds a FHIRPath expression compares against, as written.
    static func linkIDs(in expression: String) -> [String] {
        guard let pattern else {
            return []
        }
        let range = NSRange(expression.startIndex..., in: expression)
        return pattern.matches(in: expression, range: range).compactMap { match in
            Range(match.range(at: 1), in: expression).map { String(expression[$0]) }
        }
    }
}


enum ReferenceCycle {
    /// The shortest cycle reachable in a reference graph, as the path that closes it, empty when there is none.
    static func firstCycle(in edges: [String: Set<String>], startingFrom roots: [String]) -> [String] {
        var visited: Set<String> = []
        var stack: [String] = []
        var onStack: Set<String> = []

        func visit(_ node: String) -> [String] {
            if let index = stack.firstIndex(of: node), onStack.contains(node) {
                return Array(stack[index...]) + [node]
            }
            guard visited.insert(node).inserted else {
                return []
            }
            stack.append(node)
            onStack.insert(node)
            defer {
                stack.removeLast()
                onStack.remove(node)
            }
            for next in (edges[node] ?? []).sorted() {
                let cycle = visit(next)
                if !cycle.isEmpty {
                    return cycle
                }
            }
            return []
        }

        for root in roots {
            let cycle = visit(root)
            if !cycle.isEmpty {
                return cycle
            }
        }
        return []
    }
}


enum EditDistance {
    /// Levenshtein distance, capped: anything beyond `limit` is reported as `limit + 1`.
    static func between(_ lhs: String, _ rhs: String, limit: Int) -> Int {
        guard abs(lhs.count - rhs.count) <= limit else {
            return limit + 1
        }
        let source = Array(lhs)
        let target = Array(rhs)
        guard !source.isEmpty, !target.isEmpty else {
            return max(source.count, target.count)
        }
        var previous = Array(0...target.count)
        var current = previous
        for row in 1...source.count {
            current[0] = row
            for column in 1...target.count {
                current[column] = source[row - 1] == target[column - 1]
                    ? previous[column - 1]
                    : min(previous[column - 1], previous[column], current[column - 1]) + 1
            }
            previous = current
        }
        return previous[target.count]
    }
}


/// Collects the names an expression mentions, ignoring the member half of member accesses
/// so `mood.selected(.notAtAll)` reports `mood` and nothing else.
final class ReferenceCollector: SyntaxVisitor {
    private(set) var references: [InstrumentReference] = []

    static func references(in syntax: some SyntaxProtocol) -> [InstrumentReference] {
        let collector = ReferenceCollector(viewMode: .sourceAccurate)
        collector.walk(syntax)
        return collector.references
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        guard let base = node.base else {
            return .visitChildren
        }
        let path = InstrumentSyntax.dottedName(of: base)
        guard path.count == 1 else {
            return .visitChildren
        }
        // An uppercase base names a type, so the member is the reference (`GAD7.worry`);
        // a lowercase one is a value, so the base itself is (`mood.selected(…)`).
        if path[0].first?.isUppercase == true {
            references.append(
                InstrumentReference(qualifier: path[0], name: node.declName.baseName.text, node: ExprSyntax(node))
            )
        } else {
            references.append(InstrumentReference(qualifier: nil, name: path[0], node: base))
        }
        return .skipChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        // The member half of `foo.bar` names a member, not a declaration in scope.
        if let member = node.parent?.as(MemberAccessExprSyntax.self), member.declName == node {
            return .skipChildren
        }
        references.append(InstrumentReference(qualifier: nil, name: node.baseName.text, node: ExprSyntax(node)))
        return .skipChildren
    }
}
