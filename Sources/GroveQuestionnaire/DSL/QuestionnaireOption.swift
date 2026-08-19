//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// The closed set of answer options a ``ChoiceQuestion`` offers.
///
/// A `String`-backed enum declares the options once: the raw values are the codes — the
/// stable wire identity — and `allCases`, in declaration order, is the exported
/// `answerOption` list. Referencing an option that does not exist is then a compile error
/// rather than a branch that silently never fires.
///
/// ```swift
/// enum Frequency: String, QuestionnaireOption {
///     case notAtAll = "not-at-all"
///     case severalDays = "several-days"
///     case nearlyEveryDay = "nearly-every-day"
///
///     static let system = URL(string: "https://example.org/fhir/CodeSystem/phq9-frequency")
///
///     var title: String {
///         switch self {
///         case .notAtAll: "Not at all"
///         case .severalDays: "Several days"
///         case .nearlyEveryDay: "Nearly every day"
///         }
///     }
/// }
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol QuestionnaireOption: RawRepresentable, CaseIterable, Hashable, Sendable where RawValue == String {
    /// The code system every case belongs to; `nil` uses the questionnaire-local system.
    static var system: URL? { get }

    /// The user-displayed label.
    var title: String { get }

    /// A scoring weight (FHIR `itemWeight`), enabling `weight()`-based scores.
    var weight: Decimal? { get }

    /// Whether selecting this option clears all others (`questionnaire-optionExclusive`) —
    /// for "None of the above" style options.
    var isExclusive: Bool { get }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireOption {
    /// Leaves the options in the questionnaire-local system, so they need no external code system.
    public static var system: URL? {
        nil
    }

    static var choices: [Choice] {
        allCases.map { option in
            var choice = Choice(option.rawValue, option.title)
            choice.weight = option.weight
            choice.isExclusive = option.isExclusive
            return choice
        }
    }

    /// Leaves the option unweighted, so it contributes nothing to a `weight()`-based score.
    public var weight: Decimal? {
        nil
    }

    /// Lets the option be selected alongside the others.
    public var isExclusive: Bool {
        false
    }
}
