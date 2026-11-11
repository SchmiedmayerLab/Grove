//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

package import ModelsR4


/// One Device snapshot, the content key every reference to it resolves through, and the fullUrl it is stated at.
///
/// Every adapter keys device snapshots the same way, so the pairing lives here rather than being
/// redeclared per producer.
package struct IdentifiedDevice: Sendable {
    package let resource: Device
    package let identity: RoledIdentifier
    /// ``identity``'s fullUrl, for the snapshot's entry and every reference to it.
    package let url: String

    /// The snapshot's Bundle entry, keyed by ``identity`` at ``url``.
    package var entry: BundleEntry {
        BundleEntry(identifier: identity, fullURL: url, resource: ResourceProxy(with: resource))
    }

    /// Keys `body`, which must be final and state every node it references, and adds the key as its first identifier.
    package init(
        keying body: Device,
        role: OpaqueIdentityScope.NodeRole,
        subject: BusinessIdentifier,
        identityScope: OpaqueIdentityScope
    ) throws(ExchangeIdentityError) {
        let identity = try identityScope.contentSnapshot(of: body, subject: subject, role: role)
        var resource = body
        resource.identifier = [identity.fhirIdentifier] + (body.identifier ?? [])
        self.resource = resource
        self.identity = identity
        self.url = try identity.fullURLString
    }
}
