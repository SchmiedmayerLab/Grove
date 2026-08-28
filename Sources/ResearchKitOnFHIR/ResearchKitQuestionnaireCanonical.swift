//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if ResearchKit

import Foundation


/// Shared canonical validation for both directions of the ResearchKit adapter.
enum ResearchKitQuestionnaireCanonical {
    static func isValidURL(_ value: String) -> Bool {
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              !value.contains("|"),
              !value.contains("#"),
              let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false,
              components.fragment == nil else {
            return false
        }
        return true
    }

    /// Exact SemVer 2.0.0 grammar without a machine-integer width limit.
    static func isSemanticVersion(_ value: String) -> Bool {
        let buildParts = value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        guard buildParts.count <= 2,
              buildParts.count == 1 || validIdentifiers(buildParts[1], enforcesNumericLeadingZeroRule: false) else {
            return false
        }

        let prereleaseParts = buildParts[0].split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard prereleaseParts.count <= 2,
              prereleaseParts.count == 1
                || validIdentifiers(prereleaseParts[1], enforcesNumericLeadingZeroRule: true) else {
            return false
        }

        let core = prereleaseParts[0].split(separator: ".", omittingEmptySubsequences: false)
        return core.count == 3 && core.allSatisfy(isCanonicalNonnegativeDecimal)
    }

    private static func validIdentifiers(
        _ value: Substring,
        enforcesNumericLeadingZeroRule: Bool
    ) -> Bool {
        let identifiers = value.split(separator: ".", omittingEmptySubsequences: false)
        return !identifiers.isEmpty && identifiers.allSatisfy { identifier in
            guard !identifier.isEmpty,
                  identifier.utf8.allSatisfy({ byte in
                      (0x30...0x39).contains(byte)
                          || (0x41...0x5A).contains(byte)
                          || (0x61...0x7A).contains(byte)
                          || byte == 0x2D
                  }) else {
                return false
            }
            guard enforcesNumericLeadingZeroRule,
                  identifier.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else {
                return true
            }
            return identifier == "0" || identifier.utf8.first != 0x30
        }
    }

    private static func isCanonicalNonnegativeDecimal(_ value: Substring) -> Bool {
        guard let first = value.utf8.first else {
            return false
        }
        if first == 0x30 {
            return value.utf8.count == 1
        }
        return (0x31...0x39).contains(first)
            && value.utf8.dropFirst().allSatisfy { (0x30...0x39).contains($0) }
    }
}

#endif
