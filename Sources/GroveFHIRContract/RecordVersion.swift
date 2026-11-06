//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// A record's retry identity: the entry key of its lifecycle Provenance.
///
/// A conversion's is the keyed `record-version` over its source record and record content, so an exact retry repeats it
/// and any change to the record is a new version of the source record. A retraction's is the keyed `record-retraction`
/// over its source record alone. Only a holder of the identity key can recompute either: a receiver compares them.
public struct RecordVersion: Hashable, Sendable {
    /// The key: role `record-version` on a conversion Provenance, `record-retraction` on a retraction Provenance.
    public let identifier: RoledIdentifier
    /// The Provenance's fullUrl.
    public let fullURL: String

    /// Reads a Provenance's entry key, shape only: the value is keyed.
    package init(_ identifier: RoledIdentifier) throws(ExchangeIdentityError) {
        guard identifier.role == .recordVersion || identifier.role == .recordRetraction else {
            throw .invalidIdentifierRole(identifier.role.rawValue)
        }
        guard ExchangeIdentity.isCanonicalOpaqueIdentifierValue(identifier.identifier.value) else {
            throw .invalidRecordVersion(identifier.identifier.value)
        }
        self.identifier = identifier
        self.fullURL = try identifier.fullURLString
    }
}
