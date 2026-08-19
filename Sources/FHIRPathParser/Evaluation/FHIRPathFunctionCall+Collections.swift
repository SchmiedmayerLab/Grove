//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Antlr4


extension FHIRPathFunctionCall {
    // MARK: Existence

    func evaluateExistence() throws -> [FHIRPathValue] {
        switch name {
        case "empty":
            try requireParams(0...0)
            return [.boolean(input.isEmpty)]
        case "exists":
            try requireParams(0...1)
            if params.isEmpty {
                return [.boolean(!input.isEmpty)]
            }
            let matches = try iterate(0) { criteria, item in
                try FHIRPathEvaluator.singletonBoolean(of: criteria) == .true ? [item] : []
            }
            return [.boolean(!matches.isEmpty)]
        case "all":
            try requireParams(1...1)
            let failures = try iterate(0) { criteria, item in
                try FHIRPathEvaluator.singletonBoolean(of: criteria) == .true ? [] : [item]
            }
            return [.boolean(failures.isEmpty)]
        case "allTrue":
            return [.boolean(input.allSatisfy { $0 == .boolean(true) })]
        case "anyTrue":
            return [.boolean(input.contains(.boolean(true)))]
        case "allFalse":
            return [.boolean(input.allSatisfy { $0 == .boolean(false) })]
        case "anyFalse":
            return [.boolean(input.contains(.boolean(false)))]
        default:
            return try evaluateCardinality()
        }
    }

    // MARK: Cardinality

    private func evaluateCardinality() throws -> [FHIRPathValue] {
        switch name {
        case "count":
            try requireParams(0...0)
            return [.integer(input.count)]
        case "distinct":
            var seen: [FHIRPathValue] = []
            for value in input where !seen.contains(value) {
                seen.append(value)
            }
            return seen
        case "isDistinct":
            var seen: [FHIRPathValue] = []
            for value in input {
                if seen.contains(value) {
                    return [.boolean(false)]
                }
                seen.append(value)
            }
            return [.boolean(true)]
        case "hasValue":
            return [.boolean(input.count == 1 && { if case .object = input[0] { false } else { true } }())]
        default:
            return try evaluateProjection()
        }
    }

    // MARK: Filtering & Projection

    private func evaluateProjection() throws -> [FHIRPathValue] {
        switch name {
        case "where":
            try requireParams(1...1)
            return try iterate(0) { criteria, item in
                try FHIRPathEvaluator.singletonBoolean(of: criteria) == .true ? [item] : []
            }
        case "select":
            try requireParams(1...1)
            return try iterate(0) { value, _ in value }
        case "extension":
            try requireParams(1...1)
            guard case .string(let url)? = try param(0).singleton else {
                return []
            }
            return input.flatMap { value -> [FHIRPathValue] in
                guard case .object(let node) = value else {
                    return []
                }
                return node.children(named: "extension")
                    .filter { $0.stringMember("url") == url }
                    .map(FHIRPathValue.init(node:))
            }
        case "ofType":
            try requireParams(1...1)
            let typeName = params[0].getText()
            return try input.filter { try FHIRPathEvaluator.matchesType($0, name: typeName) }
        default:
            return try evaluateSubsetting()
        }
    }

    // MARK: Subsetting

    private func evaluateSubsetting() throws -> [FHIRPathValue] {
        switch name {
        case "first":
            return input.first.map { [$0] } ?? []
        case "last":
            return input.last.map { [$0] } ?? []
        case "tail":
            return Array(input.dropFirst())
        case "skip":
            try requireParams(1...1)
            guard case .integer(let count)? = try param(0).singleton else {
                return []
            }
            return Array(input.dropFirst(Swift.max(0, count)))
        case "take":
            try requireParams(1...1)
            guard case .integer(let count)? = try param(0).singleton else {
                return []
            }
            return Array(input.prefix(Swift.max(0, count)))
        case "single":
            guard input.count <= 1 else {
                throw FHIRPathEvaluationError.typeMismatch("single() on a collection with \(input.count) items")
            }
            return input
        default:
            return try evaluateTraversal()
        }
    }

    // MARK: Traversal & Combining

    private func evaluateTraversal() throws -> [FHIRPathValue] {
        switch name {
        case "children":
            return input.flatMap { value -> [FHIRPathValue] in
                guard case .object(let node) = value else {
                    return []
                }
                return node.allChildren.map(FHIRPathValue.init(node:))
            }
        case "descendants":
            return input.flatMap { value -> [FHIRPathValue] in
                guard case .object(let node) = value else {
                    return []
                }
                return node.allDescendants.map(FHIRPathValue.init(node:))
            }
        case "combine":
            try requireParams(1...1)
            return try input + param(0)
        case "union":
            try requireParams(1...1)
            var result = input
            for value in try param(0) where !result.contains(value) {
                result.append(value)
            }
            return result
        default:
            return try evaluateConversion()
        }
    }
}
