//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

package import ModelsR4


/// One Device snapshot, the minted identity every graph reference resolves to, and the fullUrl it is stated at.
///
/// Every adapter mints device snapshots the same way, so the pairing lives here rather than being
/// redeclared per producer.
package struct IdentifiedDevice: Sendable {
    package var resource: Device
    package let identity: RoledIdentifier
    /// ``identity``'s fullUrl, for the snapshot's entry and every reference to it.
    package let url: String

    /// The snapshot's Bundle entry, keyed by ``identity`` at ``url``.
    package var entry: BundleEntry {
        BundleEntry(identifier: identity, fullURL: url, resource: ResourceProxy(with: resource))
    }

    package init(resource: Device, identity: RoledIdentifier) throws(ExchangeIdentityError) {
        self.resource = resource
        self.identity = identity
        self.url = try identity.fullURLString
    }
}
