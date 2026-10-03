//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
@testable import GroveFHIRContract


/// Compares two token trees the way the exchange protocol does: member order is free, array order and number
/// lexemes are not. The goldens and the content corpus report drift through it.
enum TokenDiff {
    /// One place where two token trees differ, with what each states there; nil where one states nothing.
    struct Difference: CustomStringConvertible {
        /// Where the trees differ, as `$.member[index]...`.
        let path: String
        /// The checked-in tree's value at `path`.
        let expected: LosslessJSONValue?
        /// The actual tree's value at `path`.
        let actual: LosslessJSONValue?
        /// What differs when the values alone do not say it: a member name that differs only in its Unicode scalars.
        var detail: String?

        var description: String {
            if let detail {
                return "\(path): \(detail)"
            }
            return switch (expected, actual) {
            case let (expected?, actual?):
                "\(path): golden \(TokenDiff.summary(expected)), actual \(TokenDiff.summary(actual))"
            case let (nil, actual?):
                "\(path): golden has no such member, actual is \(TokenDiff.summary(actual))"
            case let (expected?, nil):
                "\(path): missing, golden has \(TokenDiff.summary(expected))"
            case (nil, nil):
                path
            }
        }

        /// The change as a corpus change report states it: both values in full, `(absent)` for a missing one.
        var change: String {
            "\(path): \(expected?.canonicalText ?? "(absent)") -> \(actual?.canonicalText ?? "(absent)")"
        }
    }

    /// The first path where two token trees differ, or nil when they are equal.
    static func firstDifference(expected: LosslessJSONValue, actual: LosslessJSONValue) -> String? {
        differences(expected: expected, actual: actual, limit: 1).first?.description
    }

    /// Every place, up to `limit`, where two token trees differ: objects and arrays are walked into, so each
    /// difference is a leaf, a member or element only one tree has, or a value whose kind differs.
    static func differences(expected: LosslessJSONValue, actual: LosslessJSONValue, limit: Int = .max) -> [Difference] {
        var found: [Difference] = []
        collect(expected: expected, actual: actual, at: "$", limit: limit, into: &found)
        return found
    }

    /// Appends every difference below `path`, stopping once `limit` are found.
    private static func collect(
        expected: LosslessJSONValue,
        actual: LosslessJSONValue,
        at path: String,
        limit: Int,
        into found: inout [Difference]
    ) {
        switch (expected, actual) {
        case let (.object(lhs), .object(rhs)):
            let before = found.count
            for key in Set(lhs.keys).union(rhs.keys).sorted() where found.count < limit {
                collectPresent(expected: lhs[key], actual: rhs[key], at: "\(path).\(key)", limit: limit, into: &found)
            }
            // Every value matched under a dictionary lookup, which finds canonically equivalent names alike.
            if found.count == before, found.count < limit, expected != actual {
                found.append(Difference(path: path, expected: expected, actual: actual, detail: "a member name differs in its Unicode scalars"))
            }
        case let (.array(lhs), .array(rhs)):
            for index in 0..<max(lhs.count, rhs.count) where found.count < limit {
                collectPresent(
                    expected: lhs.indices.contains(index) ? lhs[index] : nil,
                    actual: rhs.indices.contains(index) ? rhs[index] : nil,
                    at: "\(path)[\(index)]",
                    limit: limit,
                    into: &found
                )
            }
        default:
            if expected != actual, found.count < limit {
                found.append(Difference(path: path, expected: expected, actual: actual))
            }
        }
    }

    /// A member or element one tree may lack: a difference of its own then, else compared in depth.
    private static func collectPresent(
        expected: LosslessJSONValue?,
        actual: LosslessJSONValue?,
        at path: String,
        limit: Int,
        into found: inout [Difference]
    ) {
        guard let expected, let actual else {
            if found.count < limit {
                found.append(Difference(path: path, expected: expected, actual: actual))
            }
            return
        }
        collect(expected: expected, actual: actual, at: path, limit: limit, into: &found)
    }

    /// A value as a drift message names it: scalars in full, objects and arrays by size.
    private static func summary(_ value: LosslessJSONValue) -> String {
        switch value {
        case .object(let members): "object(\(members.count) members)"
        case .array(let elements): "array(\(elements.count))"
        case .string(let text): "\"" + text.unicodeScalars.map { $0.isASCII ? String($0) : "\\u{\(String($0.value, radix: 16))}" }.joined() + "\""
        case .number(let lexeme): lexeme
        case .boolean(let flag): "\(flag)"
        case .null: "null"
        }
    }
}


extension LosslessJSONValue {
    /// The elements of an array, or nil for any other kind.
    var elements: [LosslessJSONValue]? { // swiftlint:disable:this discouraged_optional_collection
        guard case .array(let elements) = self else {
            return nil
        }
        return elements
    }

    /// The text of a string, or nil for any other kind.
    var text: String? {
        guard case .string(let text) = self else {
            return nil
        }
        return text
    }

    /// Compact JSON with members sorted by key, number lexemes kept as read, and every invisible scalar escaped:
    /// two values print alike exactly when their tokens are equal and their strings hold the same scalars, so a
    /// corpus line diffs by content.
    var canonicalText: String {
        var text = ""
        append(to: &text)
        return text
    }

    /// Whether a scalar prints as an escape: controls, and format and separator characters (a byte order mark,
    /// U+2028) a reader would not see in the file.
    static func isEscaped(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator: true
        default: false
        }
    }

    /// `\uXXXX` for each UTF-16 code unit of `scalar`.
    static func escape(_ scalar: Unicode.Scalar) -> String {
        String(scalar).utf16.map { String(format: "\\u%04x", $0) }.joined()
    }

    /// Appends `string` as a JSON string literal.
    private static func append(_ string: String, to text: inout String) {
        text.append("\"")
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": text.append("\\\"")
            case "\\": text.append("\\\\")
            case "\n": text.append("\\n")
            case "\r": text.append("\\r")
            case "\t": text.append("\\t")
            case _ where isEscaped(scalar): text.append(escape(scalar))
            default: text.unicodeScalars.append(scalar)
            }
        }
        text.append("\"")
    }

    /// Appends the value's canonical text.
    private func append(to text: inout String) {
        switch self {
        case .object(let members):
            text.append("{")
            for (index, key) in members.keys.sorted().enumerated() {
                text.append(index == 0 ? "" : ",")
                Self.append(key, to: &text)
                text.append(":")
                members[key]?.append(to: &text)
            }
            text.append("}")
        case .array(let elements):
            text.append("[")
            for (index, element) in elements.enumerated() {
                text.append(index == 0 ? "" : ",")
                element.append(to: &text)
            }
            text.append("]")
        case .string(let string):
            Self.append(string, to: &text)
        case .number(let lexeme):
            text.append(lexeme)
        case .boolean(let flag):
            text.append(flag ? "true" : "false")
        case .null:
            text.append("null")
        }
    }

    /// The value of an object's member, or nil when there is none or the value is no object.
    subscript(member: String) -> LosslessJSONValue? {
        guard case .object(let members) = self else {
            return nil
        }
        return members[member]
    }
}

#endif
