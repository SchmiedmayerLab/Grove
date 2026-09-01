//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveQuestionnaire


/// Resolves a FHIR Coding against the closed options on one questionnaire item.
///
/// A system-qualified Coding is always an exact `(system, code)` match. A Coding that
/// genuinely omits `system` may use code-only matching, but only when that code identifies
/// exactly one option. Picking the first suffix match would make option order change clinical
/// meaning when two code systems reuse the same code.
@available(iOS 18, macOS 15, watchOS 11, *)
enum ChoiceOptionResolver {
    typealias Option = GroveQuestionnaire.Questionnaire.Task.Kind.ChoiceConfig.Option

    enum ResolutionError: LocalizedError, Equatable {
        case ambiguousCode(code: String, optionIDs: [String])

        var errorDescription: String? {
            switch self {
            case let .ambiguousCode(code, optionIDs):
                "Code-only choice '\(code)' is ambiguous across options: \(optionIDs.joined(separator: ", "))."
            }
        }
    }

    static func coding(system: URL?, code: String, in options: [Option]) throws -> Option? {
        if let system {
            return options.first {
                $0.fhirCoding?.system == system && $0.fhirCoding?.code == code
            }
        }
        return try codeOnly(code, in: options)
    }

    /// Resolves a native option token. A token containing `|` is already qualified and
    /// therefore only matches an exact option id. A bare token is a code-only input.
    static func token(_ token: String, in options: [Option]) throws -> Option? {
        guard !token.contains("|") else {
            return options.first { $0.id == token }
        }
        return try codeOnly(token, in: options)
    }

    private static func codeOnly(_ code: String, in options: [Option]) throws -> Option? {
        let candidates = options.filter { option in
            option.id == code || option.fhirCoding?.code == code
        }
        guard candidates.count <= 1 else {
            throw ResolutionError.ambiguousCode(
                code: code,
                optionIDs: candidates.map(\.id).sorted()
            )
        }
        return candidates.first
    }
}
