//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// The durable business identifier of one active or retraction exchange event.
public struct ExchangeEventIdentifier: Hashable, Sendable {
    public let businessIdentifier: BusinessIdentifier
    public let producerInstance: UUID
    public let sequence: CanonicalPositiveDecimal

    public init(
        system: IdentifierSystem,
        producerInstance: UUID,
        sequence: CanonicalPositiveDecimal
    ) throws {
        let canonicalUUID = producerInstance.uuidString.lowercased()
        let uuidCharacters = Array(canonicalUUID)
        guard ("1"..."5").contains(String(uuidCharacters[14])),
              "89ab".contains(uuidCharacters[19]) else {
            throw ExchangeIdentityError.invalidProducerInstance(producerInstance)
        }
        self.producerInstance = producerInstance
        self.sequence = sequence
        self.businessIdentifier = try BusinessIdentifier(
            system: system,
            value: "e0:\(canonicalUUID):\(sequence.rawValue)",
            role: .event
        )
    }

    /// Convenience for callers whose local event counter is currently machine-sized.
    public init(
        system: IdentifierSystem,
        producerInstance: UUID,
        sequence: UInt64
    ) throws {
        do {
            try self.init(
                system: system,
                producerInstance: producerInstance,
                sequence: CanonicalPositiveDecimal(sequence)
            )
        } catch let error as CanonicalDecimalError {
            throw ExchangeIdentityError.invalidEventSequence(String(sequence), underlying: error)
        }
    }

    /// Validates a persisted identifier before exact replay.
    public init(_ identifier: BusinessIdentifier) throws {
        guard identifier.role == .event else {
            throw ExchangeIdentityError.invalidIdentifierRole(
                identifier.role?.rawValue ?? "missing"
            )
        }
        let components = identifier.value.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0] == "e0",
              let uuid = UUID(uuidString: String(components[1])),
              uuid.uuidString.lowercased() == components[1],
              let sequence = try? CanonicalPositiveDecimal(String(components[2])) else {
            throw ExchangeIdentityError.invalidEventIdentifier(identifier.value)
        }
        let uuidCharacters = Array(components[1])
        guard ("1"..."5").contains(String(uuidCharacters[14])),
              "89ab".contains(uuidCharacters[19]) else {
            throw ExchangeIdentityError.invalidEventIdentifier(identifier.value)
        }
        self.businessIdentifier = identifier
        self.producerInstance = uuid
        self.sequence = sequence
    }
}
