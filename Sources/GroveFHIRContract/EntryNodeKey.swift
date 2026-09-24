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


/// The deterministic, event-scoped `n0:` key of an entry whose resource has no business identifier.
public struct EntryNodeKey: Hashable, Sendable {
    public let identifier: RoledIdentifier
    public let nodeRole: String
    public let ordinal: CanonicalNonnegativeDecimal

    public init(
        system: IdentifierSystem,
        event: ExchangeEventIdentifier,
        nodeRole: String,
        ordinal: UInt64
    ) throws(ExchangeIdentityError) {
        try self.init(system: system, event: event, nodeRole: nodeRole, ordinal: CanonicalNonnegativeDecimal(ordinal))
    }

    package init(
        system: IdentifierSystem,
        event: ExchangeEventIdentifier,
        nodeRole: String,
        ordinal: CanonicalNonnegativeDecimal
    ) throws(ExchangeIdentityError) {
        guard let first = nodeRole.utf8.first,
              (0x61...0x7A).contains(first),
              nodeRole.utf8.allSatisfy({
                  (0x61...0x7A).contains($0) || (0x30...0x39).contains($0) || $0 == 0x2D
              }) else {
            throw .invalidEntryNodeRole
        }
        let framed: Data
        do {
            framed = try LengthFramedUTF8.encode([
                "org.grovealliance.fhir.entry-node.v0",
                event.identifier.identifier.system.rawValue,
                event.identifier.identifier.value,
                nodeRole,
                ordinal.rawValue
            ])
        } catch {
            switch error {
            case .componentTooLarge(let byteCount):
                throw .identityComponentTooLarge(byteCount)
            default:
                throw .identityFramingFailure
            }
        }
        let digest = Data(SHA256.hash(data: framed)).base64URLEncodedStringWithoutPadding
        self.identifier = RoledIdentifier(
            identifier: BusinessIdentifier(system: system, nonemptyValue: "n0:\(nodeRole):\(ordinal.rawValue):\(digest)"),
            role: .entryNode
        )
        self.nodeRole = nodeRole
        self.ordinal = ordinal
    }

    /// Validates a persisted entry-node key against its owning event.
    package init(_ identifier: RoledIdentifier, event: ExchangeEventIdentifier) throws(ExchangeIdentityError) {
        guard identifier.role == .entryNode else {
            throw .invalidEntryNodeRole
        }
        guard let claim = Self.claim(in: identifier) else {
            throw .invalidEntryNodeValue(identifier.identifier.value)
        }
        let expected = try Self(
            system: identifier.identifier.system,
            event: event,
            nodeRole: claim.nodeRole,
            ordinal: claim.ordinal
        )
        guard expected.identifier == identifier else {
            throw .invalidEntryNodeValue(identifier.identifier.value)
        }
        self = expected
    }

    /// The node-role and ordinal a persisted key states, read before any digest verification.
    static func claim(in identifier: RoledIdentifier) -> (nodeRole: String, ordinal: CanonicalNonnegativeDecimal)? {
        let fields = identifier.identifier.value.split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 4,
              fields[0] == "n0",
              let ordinal = try? CanonicalNonnegativeDecimal(String(fields[2])) else {
            return nil
        }
        return (String(fields[1]), ordinal)
    }
}
