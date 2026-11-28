//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// Every item instance of a response, in document order, with the enablement `enableWhen` gives it.
///
/// The response holds an instance of each Questionnaire item wherever the item can appear, also where the
/// response omits it: once in every instance of an enclosing group, and once beneath every answer of an
/// enclosing question, or once if that question has no answer. A condition thereby reads the instance
/// a participant sees.
@available(iOS 18, macOS 15, watchOS 11, *)
struct PairOccurrences {
    struct Occurrence {
        let definition: FHIRJSONObject
        let linkID: String
        let parent: Int?
        let answers: [PairCondition]
        /// `<container path>.<linkId>`, the path an item's expressions are evaluated at.
        let expressionPath: String
    }

    /// The answer values a condition compares with an answer of a choice item, beyond `answerTypes`.
    ///
    /// They are the `answerOption.value[x]` types. An answer of such a type is reported as an `answerType`
    /// issue, and still counts for enablement, so that a condition with one of these types can be met.
    private static let conditionAnswerTypes: [String: Set<String>] = [
        "choice": ["valueString", "valueInteger", "valueDate", "valueTime"],
        "open-choice": ["valueInteger", "valueDate", "valueTime"]
    ]

    private(set) var occurrences: [Occurrence] = []
    private var byLinkID: [String: [Int]] = [:]
    /// The occurrence at each response item path, and at `<container path>.<linkId>` for an item the response omits.
    private(set) var byPath: [String: Int] = [:]
    /// The outcome of each occurrence's own core `enableWhen`; `nil` when it cannot be evaluated.
    private(set) var conditionStates: [Bool?] = [] // swiftlint:disable:this discouraged_optional_boolean
    /// Whether each occurrence is enabled, by its enclosing items and its own enablement; `nil` when unknown.
    private var states: [Bool?] = [] // swiftlint:disable:this discouraged_optional_boolean
    private var evaluated: [Bool] = []
    private var evaluating: Set<Int> = []
    private let rules: PairEnableWhenRules
    private let expressionEnablement: (FHIRJSONObject, String) -> Bool? // swiftlint:disable:this discouraged_optional_boolean

    /// - parameter expressionEnablement: The outcome of an item definition's `enableWhenExpression` at a path,
    ///     `nil` when it cannot be evaluated.
    init(
        definitions: [FHIRJSONObject],
        response: FHIRJSONObject,
        expressionEnablement: @escaping (FHIRJSONObject, String) -> Bool? // swiftlint:disable:this discouraged_optional_boolean
    ) {
        self.expressionEnablement = expressionEnablement
        rules = PairEnableWhenRules(definitions: definitions)
        place(
            definitions,
            responses: response["item"] as? [FHIRJSONObject] ?? [],
            parent: nil,
            path: "QuestionnaireResponse.item"
        )
        conditionStates = Array(repeating: nil, count: occurrences.count)
        states = Array(repeating: nil, count: occurrences.count)
        evaluated = Array(repeating: false, count: occurrences.count)
        for index in occurrences.indices {
            _ = state(of: index)
        }
    }

    /// The answer values that count: those of a type the item's answers have, and only the first unless the item repeats.
    private static func values(of answers: [FHIRJSONObject], for definition: FHIRJSONObject, repeats: Bool) -> [PairCondition] {
        let type = definition["type"] as? String ?? ""
        let keys = (PairRules.answerTypes[type] ?? []).union(conditionAnswerTypes[type] ?? [])
        let values = answers.compactMap { answer in
            PairRules.answerValue(answer).flatMap { keys.contains($0.key) ? PairCondition(key: $0.key, value: $0.value) : nil }
        }
        return repeats ? values : Array(values.prefix(1))
    }

    /// The instance of `linkID` that a condition of the occurrence reads.
    ///
    /// Follows FHIR R4 `Questionnaire.item.enableWhen.question`: the nearest occurrence on the ancestor axis,
    /// then on the preceding axis, then on the following axis. A condition never reads its own item.
    private func source(of linkID: String, from occurrence: Int) -> Int? {
        guard occurrences[occurrence].linkID != linkID else {
            return nil
        }
        var ancestor = occurrences[occurrence].parent
        while let index = ancestor {
            if occurrences[index].linkID == linkID {
                return index
            }
            ancestor = occurrences[index].parent
        }
        let candidates = byLinkID[linkID] ?? []
        return candidates.last { $0 < occurrence }
            ?? candidates.first { $0 > occurrence && !isDescendant($0, of: occurrence) }
    }

    private func isDescendant(_ candidate: Int, of occurrence: Int) -> Bool {
        var parent = occurrences[candidate].parent
        while let index = parent {
            if index == occurrence {
                return true
            }
            parent = occurrences[index].parent
        }
        return false
    }

    /// Whether the occurrence is enabled. An occurrence on the evaluation stack forms a reference cycle and is unknown.
    private mutating func state(of index: Int) -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
        if evaluated[index] {
            return states[index]
        }
        guard evaluating.insert(index).inserted else {
            return nil
        }
        defer {
            evaluating.remove(index)
        }
        let enclosing = occurrences[index].parent.map { state(of: $0) } ?? true
        guard !rules.cyclic.contains(occurrences[index].linkID) else {
            // An item that depends on itself has no enablement of its own; a disabled enclosing item still disables it.
            let enablement = PairCondition.all([enclosing, nil])
            states[index] = enablement
            evaluated[index] = true
            return enablement
        }
        let condition = conditionState(of: index)
        conditionStates[index] = condition
        let definition = occurrences[index].definition
        let hasExpression = !PairRules.extensions(definition, url: PairRules.URL.enableWhenExpression).isEmpty
        let own = hasExpression ? expressionEnablement(definition, occurrences[index].expressionPath) : condition
        let enablement = PairCondition.all([enclosing, own])
        states[index] = enablement
        evaluated[index] = true
        return enablement
    }

    /// The outcome of the occurrence's core `enableWhen`. The answers of a disabled question count as absent.
    private mutating func conditionState(of index: Int) -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
        let definition = occurrences[index].definition
        guard let conditions = rules.rules(of: definition) else {
            return nil
        }
        guard !conditions.isEmpty else {
            return true
        }
        let outcomes = conditions.map { rule -> Bool? in // swiftlint:disable:this discouraged_optional_boolean
            // A condition on the item itself has no other instance to read.
            guard let rule, let source = source(of: rule.question, from: index) else {
                return nil
            }
            let answers = occurrences[source].answers
            switch state(of: source) {
            case .some(true):
                return PairCondition.test(rule.operation, expected: rule.expected, answers: answers)
            case .some(false):
                return PairCondition.test(rule.operation, expected: rule.expected, answers: [])
            case .none:
                // The outcome is known when it does not depend on whether the question is enabled.
                let withAnswers = PairCondition.test(rule.operation, expected: rule.expected, answers: answers)
                let withoutAnswers = PairCondition.test(rule.operation, expected: rule.expected, answers: [])
                return withAnswers == withoutAnswers ? withAnswers : nil
            }
        }
        return definition["enableBehavior"] as? String == "any" ? PairCondition.any(outcomes) : PairCondition.all(outcomes)
    }

    private mutating func place(
        _ definitions: [FHIRJSONObject],
        responses: [FHIRJSONObject],
        parent: Int?,
        path: String
    ) {
        var found: [String: [(response: FHIRJSONObject, path: String)]] = [:]
        for (index, response) in responses.enumerated() {
            if let linkID = response["linkId"] as? String {
                found[linkID, default: []].append((response, "\(path)[\(index)]"))
            }
        }
        for definition in definitions {
            guard let linkID = definition["linkId"] as? String else {
                continue
            }
            let entries = found[linkID] ?? []
            // Only a repeating group has several instances in one container; of a duplicated item, the first counts.
            let repeats = definition["repeats"] as? Bool == true
            let counted = definition["type"] as? String == "group" && repeats ? entries : Array(entries.prefix(1))
            let instances: [(response: FHIRJSONObject?, path: String)] = counted.isEmpty
                ? [(nil, "\(path).\(linkID)")]
                : counted.map { ($0.response, $0.path) }
            for instance in instances {
                let answers = instance.response?["answer"] as? [FHIRJSONObject] ?? []
                let index = occurrences.count
                occurrences.append(Occurrence(
                    definition: definition,
                    linkID: linkID,
                    parent: parent,
                    answers: Self.values(of: answers, for: definition, repeats: repeats),
                    expressionPath: "\(path).\(linkID)"
                ))
                byLinkID[linkID, default: []].append(index)
                byPath[instance.path] = index
                placeChildren(of: definition, instance: instance, answers: answers, parent: index)
            }
            for duplicate in entries.dropFirst(counted.count) {
                byPath[duplicate.path] = byPath[counted[0].path]
            }
        }
    }

    private mutating func placeChildren(
        of definition: FHIRJSONObject,
        instance: (response: FHIRJSONObject?, path: String),
        answers: [FHIRJSONObject],
        parent: Int
    ) {
        let children = definition["item"] as? [FHIRJSONObject] ?? []
        guard !children.isEmpty else {
            return
        }
        if definition["type"] as? String == "group" {
            place(children, responses: instance.response?["item"] as? [FHIRJSONObject] ?? [], parent: parent, path: "\(instance.path).item")
        } else if answers.isEmpty {
            place(children, responses: [], parent: parent, path: "\(instance.path).answer.item")
        } else {
            for (answerIndex, answer) in answers.enumerated() {
                place(
                    children,
                    responses: answer["item"] as? [FHIRJSONObject] ?? [],
                    parent: parent,
                    path: "\(instance.path).answer[\(answerIndex)].item"
                )
            }
        }
    }
}
