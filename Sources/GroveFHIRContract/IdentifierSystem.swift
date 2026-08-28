//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// The namespace half of a FHIR business identifier: an absolute URI naming whose numbering
/// scheme a value belongs to.
///
/// Holding this as a type rather than a `String` means a malformed namespace is reported where the
/// deployment configures it, not later when a conversion is already under way.
///
/// The serialized form has to survive encoding unchanged, because exchange identities are derived
/// from these exact bytes. A URI that `Foundation` would re-serialize differently is rejected
/// rather than silently normalized.
public struct IdentifierSystem: Hashable, Sendable {
    public let rawValue: String

    /// Validates a namespace that is not known until runtime — read from configuration, a server
    /// response, or a deployment property list.
    public init(_ rawValue: String) throws(ExchangeIdentityError) {
        guard !rawValue.isEmpty else {
            throw .missingIdentifierSystem
        }
        guard let url = URL(string: rawValue), url.scheme != nil else {
            throw .invalidIdentifierSystem(rawValue)
        }
        guard url.absoluteString == rawValue else {
            throw .nonCanonicalIdentifierSystem(supplied: rawValue, encoded: url.absoluteString)
        }
        self.rawValue = rawValue
    }
}


extension IdentifierSystem: CustomStringConvertible {
    public var description: String { rawValue }
}


extension IdentifierSystem: ExpressibleByStringLiteral {
    /// The literal form takes a `StaticString`, so only a namespace written in source can be
    /// spelled this way; anything computed at runtime goes through ``init(_:)`` and reports a
    /// malformed namespace instead of trapping.
    public typealias StringLiteralType = StaticString

    public init(stringLiteral value: StaticString) {
        guard let system = try? IdentifierSystem("\(value)") else {
            preconditionFailure("'\(value)' is not an absolute URI usable as an identifier system.")
        }
        self = system
    }
}
