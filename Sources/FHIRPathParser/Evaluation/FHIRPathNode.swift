//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// A JSON-shaped view of a FHIR resource (or element), used as the data model
/// FHIRPath expressions are evaluated over.
///
/// Building evaluation on the resource's JSON form keeps the evaluator independent
/// of any particular FHIR model library: callers encode whatever resource types they
/// use (e.g. `ModelsR4`) and hand the tree to ``FHIRPathExpression``.
public indirect enum FHIRPathNode: Hashable, Sendable {
    case object([String: FHIRPathNode])
    case array([FHIRPathNode])
    case string(String)
    case number(Decimal)
    case bool(Bool)
    case null

    /// All child nodes, in stable (key-sorted) order.
    var allChildren: [FHIRPathNode] {
        switch self {
        case .object(let members):
            members.sorted { $0.key < $1.key }.flatMap { $0.value.flattened }
        case .array(let elements):
            elements
        case .string, .number, .bool, .null:
            []
        }
    }

    /// Every node below this one, depth-first: each child followed by its own descendants.
    var allDescendants: [FHIRPathNode] {
        allChildren.flatMap { child in
            if case .object = child {
                [child] + child.allDescendants
            } else {
                [child]
            }
        }
    }

    private var flattened: [FHIRPathNode] {
        switch self {
        case .array(let elements):
            elements
        case .null:
            []
        case .object, .string, .number, .bool:
            [self]
        }
    }

    /// Creates a node tree from serialized JSON.
    public init(jsonData: Data) throws {
        let object = try JSONSerialization.jsonObject(with: jsonData, options: [.fragmentsAllowed])
        guard let node = FHIRPathNode(jsonObject: object) else {
            throw FHIRPathEvaluationError.malformedInput("Input is not representable as JSON")
        }
        self = node
    }

    init?(jsonObject: Any) {
        switch jsonObject {
        case let dict as [String: Any]:
            self = .object(dict.compactMapValues { FHIRPathNode(jsonObject: $0) })
        case let array as [Any]:
            self = .array(array.compactMap { FHIRPathNode(jsonObject: $0) })
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.decimalValue)
            }
        case let string as String:
            self = .string(string)
        case is NSNull:
            self = .null
        default:
            return nil
        }
    }

    /// Creates a node tree by JSON-encoding an `Encodable` value (typically a FHIR resource).
    public static func encoding(_ value: some Encodable) throws -> FHIRPathNode {
        let data = try JSONEncoder().encode(value)
        return try FHIRPathNode(jsonData: data)
    }

    /// The node's children for an element name, honoring FHIR's choice-type naming:
    /// a member `value` also matches JSON keys like `valueQuantity` or `valueString`.
    public func children(named name: String) -> [FHIRPathNode] {
        guard case .object(let members) = self else {
            return []
        }
        if let direct = members[name] {
            return direct.flattened
        }
        // Choice elements: `value` matches `valueBoolean`, `effective` matches `effectiveDateTime`, ...
        return members
            .filter { key, _ in
                key.count > name.count && key.hasPrefix(name) && (key[key.index(key.startIndex, offsetBy: name.count)].isUppercase)
            }
            .sorted { $0.key < $1.key }
            .flatMap { $0.value.flattened }
    }

    /// The string member with the given name, if present.
    public func stringMember(_ name: String) -> String? {
        if case .string(let value) = children(named: name).first {
            value
        } else {
            nil
        }
    }
}
