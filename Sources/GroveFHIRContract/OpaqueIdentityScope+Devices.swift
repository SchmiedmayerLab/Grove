//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

extension OpaqueIdentityScope {
    /// Identifies one physical acquisition unit for one subject by its governed stable per-unit token.
    ///
    /// `tokenScope` names who assigned the token, as a platform's unit token is local to its host: the same value from
    /// two writers is two units.
    package func recordingDevice(
        adapterID: String,
        subject: BusinessIdentifier,
        tokenScope: String,
        stableUnitToken: String
    ) throws(ExchangeIdentityError) -> RoledIdentifier {
        try identifier(
            kind: .recordingDevice,
            components: [
                adapterID,
                subject.system.rawValue,
                subject.value,
                tokenScope,
                stableUnitToken
            ]
        )
    }

    /// Keys `node` by its final content, as ``contentSnapshot(subject:role:contentDigest:)`` keys it.
    ///
    /// - Parameter node: The resource as it travels, with neither its key nor an `id`.
    package func contentSnapshot(
        of node: some Encodable,
        subject: BusinessIdentifier,
        role: NodeRole
    ) throws(ExchangeIdentityError) -> RoledIdentifier {
        try contentSnapshot(subject: subject, role: role, contentDigest: try LosslessJSONValue(encoding: node).contentDigest)
    }

    /// Keys one immutable shared node by its final content, the node's Bundle entry key.
    ///
    /// Mint it after the body is final and after every node it references: the same content gives the same key in
    /// every Bundle, and changed content gives a new snapshot.
    ///
    /// - Parameter contentDigest: The node's ``LosslessJSONValue/contentDigest``.
    package func contentSnapshot(
        subject: BusinessIdentifier,
        role: NodeRole,
        contentDigest: String
    ) throws(ExchangeIdentityError) -> RoledIdentifier {
        try identifier(
            kind: role.kind,
            components: [
                subject.system.rawValue,
                subject.value,
                role.rawValue,
                contentDigest
            ]
        )
    }
}
