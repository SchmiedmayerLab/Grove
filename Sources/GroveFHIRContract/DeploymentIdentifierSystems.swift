//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// All twelve identifier systems a deployment owns: the ten opaque kinds, the event and the entry node.
public struct DeploymentIdentifierSystems: Hashable, Sendable {
    public let opaque: OpaqueIdentitySystems
    public let event: IdentifierSystem
    public let entryNode: IdentifierSystem

    public init(
        opaque: OpaqueIdentitySystems,
        event: IdentifierSystem,
        entryNode: IdentifierSystem
    ) throws(OpaqueIdentityError) {
        guard event != entryNode, !opaque.all.contains(event), !opaque.all.contains(entryNode) else {
            throw .reusedIdentifierSystem
        }
        self.opaque = opaque
        self.event = event
        self.entryNode = entryNode
    }

    private init(opaque: OpaqueIdentitySystems, uncheckedEvent event: IdentifierSystem, entryNode: IdentifierSystem) {
        self.opaque = opaque
        self.event = event
        self.entryNode = entryNode
    }

    /// The systems in the exchange protocol's recommended form under one deployment root.
    ///
    /// A rotated key uses a new key id or epoch, and with them new opaque systems; the event and
    /// entry-node systems stay with the root.
    public static func derived(
        root: IdentifierSystem,
        keyID: String,
        epoch: EventSequence
    ) throws(ExchangeIdentityError) -> Self {
        guard OpaqueIdentityScope.isValidKeyID(keyID) else {
            throw .invalidKeyID(keyID)
        }
        let deploymentRoot = root.rawValue.hasSuffix("/") ? String(root.rawValue.dropLast()) : root.rawValue
        func system(_ form: String, kind: OpaqueIdentityKind? = nil) throws(ExchangeIdentityError) -> IdentifierSystem {
            let text = form
                .replacingOccurrences(of: "<deployment-root>", with: deploymentRoot)
                .replacingOccurrences(of: "<identity-kind>", with: kind?.rawValue ?? "")
                .replacingOccurrences(of: "<key-id>", with: keyID)
                .replacingOccurrences(of: "<epoch>", with: epoch.rawValue)
            return try IdentifierSystem(text)
        }
        let form = ExchangeContract.opaqueIdentitySystemForm
        let opaque: OpaqueIdentitySystems
        do {
            opaque = try OpaqueIdentitySystems(
                sourceRecord: try system(form, kind: .sourceRecord),
                sourceOutput: try system(form, kind: .sourceOutput),
                writerRecord: try system(form, kind: .writerRecord),
                providerRecord: try system(form, kind: .providerRecord),
                providerOutput: try system(form, kind: .providerOutput),
                sourceArtifact: try system(form, kind: .sourceArtifact),
                providerArtifact: try system(form, kind: .providerArtifact),
                sourceContext: try system(form, kind: .sourceContext),
                recordingDevice: try system(form, kind: .recordingDevice),
                deviceSnapshot: try system(form, kind: .deviceSnapshot)
            )
        } catch let error as ExchangeIdentityError {
            throw error
        } catch {
            // Ten distinct kinds under one form cannot share a system.
            throw .invalidIdentifierSystem(deploymentRoot)
        }
        let event = try system(ExchangeContract.eventIdentifierSystemForm)
        let entryNode = try system(ExchangeContract.entryNodeIdentifierSystemForm)
        return Self(opaque: opaque, uncheckedEvent: event, entryNode: entryNode)
    }
}
