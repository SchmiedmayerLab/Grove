//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import ModelsR4


/// A repository-assigned logical Resource id.
///
/// Source identities and UUID URNs belong in business identifiers and Bundle fullUrls;
/// this type exists only for callers that already have a repository id assignment.
public struct RepositoryID: Hashable, Sendable {
    // Spelled out rather than matched with `Regex`, which needs iOS 16/macOS 13 and would lift
    // this module above the package deployment floor.
    private static let allowedCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-.")

    public let rawValue: String

    public var primitive: FHIRPrimitive<FHIRString> {
        rawValue.asFHIRStringPrimitive()
    }

    public init(_ rawValue: String) throws(ExchangeIdentityError) {
        guard Self.isValidFHIRID(rawValue) else {
            throw .invalidRepositoryID(rawValue)
        }
        self.rawValue = rawValue
    }

    static func isValidFHIRID(_ value: String) -> Bool {
        (1...64).contains(value.count) && value.allSatisfy(allowedCharacters.contains)
    }
}
