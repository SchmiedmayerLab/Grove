//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// The `enableWhen` conditions of a Questionnaire that can be evaluated, and the items that depend on themselves.
@available(iOS 18, macOS 15, watchOS 11, *)
struct PairEnableWhenRules {
    /// One condition that can be evaluated.
    struct Rule {
        let question: String
        let operation: String
        let expected: PairCondition
    }

    private static let operators: Set<String> = ["exists", "=", "!=", ">", "<", ">=", "<="]
    private static let orderedKinds: Set<String> = ["Decimal", "Integer", "Date", "DateTime", "Time", "Quantity"]
    /// The option kinds a condition on a choice compares. Reference answers are outside the exchange contract,
    /// so a condition with an `answerReference` cannot be evaluated.
    private static let optionKinds: Set<String> = ["Coding", "String", "Integer", "Date", "Time"]
    /// The `answer[x]` types a condition other than `exists` compares with the answers of each answerable item type.
    private static let conditionKinds: [String: Set<String>] = [
        "boolean": ["Boolean"], "decimal": ["Decimal", "Integer"], "integer": ["Decimal", "Integer"], "date": ["Date"],
        "dateTime": ["DateTime"], "time": ["Time"], "string": ["String"], "text": ["String"], "url": [], "choice": optionKinds,
        "open-choice": optionKinds, "attachment": [], "quantity": ["Quantity"]
    ]

    /// The type of each item, by its linkId, for linkIds that only one item uses.
    private let types: [String: String]
    /// The linkIds of the items whose enablement depends on itself, through conditions or enclosing items.
    private(set) var cyclic: Set<String> = []

    init(definitions: [FHIRJSONObject]) {
        var seen: Set<String> = []
        var duplicates: Set<String> = []
        var types: [String: String] = [:]
        var parents: [String: String] = [:]
        var all: [FHIRJSONObject] = []
        var pending = definitions.map { (item: $0, parent: String?.none) }
        while !pending.isEmpty {
            let (item, parent) = pending.removeFirst()
            all.append(item)
            let linkID = item["linkId"] as? String
            if let linkID {
                if !seen.insert(linkID).inserted {
                    duplicates.insert(linkID)
                }
                types[linkID] = item["type"] as? String ?? ""
                parents[linkID] = parent
            }
            pending += (item["item"] as? [FHIRJSONObject] ?? []).map { ($0, linkID) }
        }
        for duplicate in duplicates {
            types.removeValue(forKey: duplicate)
        }
        self.types = types
        var dependencies: [String: Set<String>] = [:]
        for item in all {
            guard let linkID = item["linkId"] as? String else {
                continue
            }
            // Conditions that cannot be evaluated never close a cycle.
            let questions = (item["enableWhen"] as? [FHIRJSONObject] ?? []).compactMap { rule($0)?.question }
            dependencies[linkID, default: []].formUnion(questions + (parents[linkID].map { [$0] } ?? []))
        }
        cyclic = Set(dependencies.keys.filter { start in
            var visited: Set<String> = []
            var pending = Array(dependencies[start] ?? [])
            while let next = pending.popLast() {
                if next == start {
                    return true
                }
                if visited.insert(next).inserted {
                    pending += dependencies[next] ?? []
                }
            }
            return false
        })
    }

    /// The item's conditions, each `nil` when it cannot be evaluated; `nil` when the item's enablement is invalid.
    ///
    /// A condition cannot be evaluated when it names no item, an item that several items share the linkId of,
    /// or an item without answers; when its operator is not an R4 operator; or when its answer is missing,
    /// incomplete, of a type the question's answers do not have, or without an order for an ordered operator.
    /// An item with several conditions must state `enableBehavior` as `all` or `any`.
    func rules(of definition: FHIRJSONObject) -> [Rule?]? { // swiftlint:disable:this discouraged_optional_collection
        let conditions = definition["enableWhen"] as? [FHIRJSONObject] ?? []
        let behavior = definition["enableBehavior"] as? String
        guard behavior == nil ? conditions.count <= 1 : ["all", "any"].contains(behavior) else {
            return nil
        }
        return conditions.map(rule)
    }

    private func rule(_ condition: FHIRJSONObject) -> Rule? {
        let answers = condition.filter { $0.key.hasPrefix("answer") }
        guard let question = condition["question"] as? String,
              let type = types[question], Self.conditionKinds[type] != nil,
              let operation = condition["operator"] as? String, Self.operators.contains(operation),
              answers.count == 1, let answer = answers.first,
              let expected = PairCondition(key: answer.key, value: answer.value) else {
            return nil
        }
        let kind = String(answer.key.dropFirst("answer".count))
        if operation == "exists" {
            guard kind == "Boolean" else {
                return nil
            }
            return Rule(question: question, operation: operation, expected: expected)
        }
        guard Self.conditionKinds[type]?.contains(kind) == true,
              ["=", "!="].contains(operation) || Self.orderedKinds.contains(kind) else {
            return nil
        }
        switch expected {
        case .coding(_, nil), .reference(nil):
            return nil
        case .quantity(let quantity) where quantity.value == nil || quantity.comparator != nil:
            return nil
        default:
            return Rule(question: question, operation: operation, expected: expected)
        }
    }
}
