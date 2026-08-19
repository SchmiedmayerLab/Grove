//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// An answer option of a ``DynamicChoiceQuestion`` or ``DynamicMultiChoiceQuestion``.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct Choice: Hashable, Sendable {
    let code: String
    let title: String
    let system: URL?
    var weight: Decimal?
    var isExclusive = false

    /// Creates a coded answer option.
    /// - parameter code: The option's code (its stable wire identity).
    /// - parameter title: The user-displayed label.
    /// - parameter system: The code's system; defaults to the questionnaire-local system.
    public init(_ code: String, _ title: String, system: URL? = nil) {
        self.code = code
        self.title = title
        self.system = system
    }

    /// Attaches a scoring weight (FHIR `itemWeight`), enabling `weight()`-based scores.
    public func weight(_ weight: Decimal) -> Self {
        var copy = self
        copy.weight = weight
        return copy
    }

    /// Makes selecting this option clear all others (`questionnaire-optionExclusive`) —
    /// for "None of the above" style options.
    public func exclusive() -> Self {
        var copy = self
        copy.isExclusive = true
        return copy
    }

    func option(defaultSystem: URL?) -> Questionnaire.Task.Kind.ChoiceConfig.Option {
        let system = system ?? defaultSystem
        return .init(
            id: system.map { "\($0.absoluteString)|\(code)" } ?? code,
            title: title,
            fhirCoding: system.map { .init(system: $0, code: code) },
            weight: weight,
            isExclusive: isExclusive
        )
    }
}
