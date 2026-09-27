//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import ModelsR4


/// One Device snapshot and the minted identity every graph reference resolves to.
///
/// Every adapter mints device snapshots the same way, so the pairing lives here rather than being
/// redeclared per producer.
public struct IdentifiedDevice: Sendable {
    public let resource: Device
    public let identity: RoledIdentifier

    public init(resource: Device, identity: RoledIdentifier) {
        self.resource = resource
        self.identity = identity
    }
}
