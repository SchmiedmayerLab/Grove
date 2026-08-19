//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// A `name(arguments)` invocation, together with the collection it is applied to.
struct FHIRPathFunctionCall {
    let evaluator: FHIRPathEvaluator
    let name: String
    let params: [FHIRPathParser.ExpressionContext]
    let input: [FHIRPathValue]
    let focus: [FHIRPathValue]

    /// Evaluates the call against the supported function library.
    ///
    /// Every group answers the names it implements and passes the rest on to the next one,
    /// so an unknown name falls through all of them and throws.
    func evaluate() throws -> [FHIRPathValue] {
        try evaluateExistence()
    }

    func requireParams(_ counts: ClosedRange<Int>) throws {
        guard counts.contains(params.count) else {
            throw FHIRPathEvaluationError.malformedExpression("\(name)() expects \(counts) arguments, got \(params.count)")
        }
    }

    func param(_ index: Int) throws -> [FHIRPathValue] {
        try evaluator.evaluate(params[index], focus: focus)
    }

    /// Evaluates `params[index]` once per input item, with `$this` bound to the item.
    func iterate(_ index: Int, transform: ([FHIRPathValue], FHIRPathValue) throws -> [FHIRPathValue]) throws -> [FHIRPathValue] {
        var results: [FHIRPathValue] = []
        for (itemIndex, item) in input.enumerated() {
            var itemEvaluator = evaluator
            itemEvaluator.iterationIndex = itemIndex
            let value = try itemEvaluator.evaluate(params[index], focus: [item])
            results.append(contentsOf: try transform(value, item))
        }
        return results
    }
}
