//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation


/// A deterministic, event-scoped key for a Bundle entry whose resource has no business identifier.
public struct ExchangeNodeKey: Hashable, Sendable {
    public let identifier: BusinessIdentifier
    public let nodeRole: String
    public let ordinal: CanonicalNonnegativeDecimal

    public init(
        system: IdentifierSystem,
        eventIdentifier: ExchangeEventIdentifier,
        nodeRole: String,
        ordinal: CanonicalNonnegativeDecimal
    ) throws {
        guard let first = nodeRole.utf8.first,
              (0x61...0x7A).contains(first),
              nodeRole.utf8.allSatisfy({
                  (0x61...0x7A).contains($0) || (0x30...0x39).contains($0) || $0 == 0x2D
              }) else {
            throw ExchangeIdentityError.invalidEntryNodeRole
        }
        let framed = try LengthFramedUTF8.encode([
            "org.grovealliance.fhir.entry-node.v0",
            eventIdentifier.businessIdentifier.systemValue,
            eventIdentifier.businessIdentifier.value,
            nodeRole,
            ordinal.rawValue
        ])
        let digest = Data(SHA256.hash(data: framed)).base64URLEncodedStringWithoutPadding
        self.identifier = try BusinessIdentifier(
            system: system,
            value: "n0:\(nodeRole):\(ordinal.rawValue):\(digest)",
            role: .entryNode
        )
        self.nodeRole = nodeRole
        self.ordinal = ordinal
    }

    /// Convenience for locally machine-sized node ordinals.
    public init(
        system: IdentifierSystem,
        eventIdentifier: ExchangeEventIdentifier,
        nodeRole: String,
        ordinal: UInt64
    ) throws {
        try self.init(
            system: system,
            eventIdentifier: eventIdentifier,
            nodeRole: nodeRole,
            ordinal: CanonicalNonnegativeDecimal(ordinal)
        )
    }

    /// Validates a persisted entry-node key against its owning event.
    public init(
        _ identifier: BusinessIdentifier,
        eventIdentifier: ExchangeEventIdentifier
    ) throws {
        guard identifier.role == .entryNode else {
            throw ExchangeIdentityError.invalidEntryNodeRole
        }
        guard let claim = Self.claim(in: identifier) else {
            throw ExchangeIdentityError.invalidEntryNodeValue(identifier.value)
        }
        let expected = try Self(
            system: identifier.system,
            eventIdentifier: eventIdentifier,
            nodeRole: claim.nodeRole,
            ordinal: claim.ordinal
        )
        guard expected.identifier == identifier else {
            throw ExchangeIdentityError.invalidEntryNodeValue(identifier.value)
        }
        self = expected
    }

    /// The node-role and ordinal a persisted key states, read before any digest verification.
    static func claim(in identifier: BusinessIdentifier) -> (nodeRole: String, ordinal: CanonicalNonnegativeDecimal)? {
        let fields = identifier.value.split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 4,
              fields[0] == "n0",
              let ordinal = try? CanonicalNonnegativeDecimal(String(fields[2])) else {
            return nil
        }
        return (String(fields[1]), ordinal)
    }
}
