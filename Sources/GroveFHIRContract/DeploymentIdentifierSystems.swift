//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// All twelve identifier systems a deployment owns: one per opaque identity kind, the event's and the entry node's.
///
/// ``derived(root:keyID:epoch:)`` forms them as the exchange protocol recommends; ``OpaqueIdentityScope`` holds them
/// with the key.
public struct DeploymentIdentifierSystems: Hashable, Sendable {
    public let sourceRecord: IdentifierSystem
    public let sourceOutput: IdentifierSystem
    public let writerRecord: IdentifierSystem
    public let providerRecord: IdentifierSystem
    public let providerOutput: IdentifierSystem
    public let sourceArtifact: IdentifierSystem
    public let providerArtifact: IdentifierSystem
    public let sourceContext: IdentifierSystem
    public let recordingDevice: IdentifierSystem
    public let deviceSnapshot: IdentifierSystem
    public let event: IdentifierSystem
    public let entryNode: IdentifierSystem

    /// Every system the deployment reserves for its graph identities: each opaque kind's, derived from the closed kind
    /// list so a new kind cannot slip past a privacy check, then the event's and the entry node's.
    package var all: [IdentifierSystem] {
        OpaqueIdentityKind.allCases.map { self[$0] } + [event, entryNode]
    }

    /// Twelve systems as stated. ``derived(root:keyID:epoch:)``, the only public way to form them, yields twelve
    /// distinct systems by construction; a test that states its own keeps them distinct.
    package init(
        sourceRecord: IdentifierSystem,
        sourceOutput: IdentifierSystem,
        writerRecord: IdentifierSystem,
        providerRecord: IdentifierSystem,
        providerOutput: IdentifierSystem,
        sourceArtifact: IdentifierSystem,
        providerArtifact: IdentifierSystem,
        sourceContext: IdentifierSystem,
        recordingDevice: IdentifierSystem,
        deviceSnapshot: IdentifierSystem,
        event: IdentifierSystem,
        entryNode: IdentifierSystem
    ) {
        self.sourceRecord = sourceRecord
        self.sourceOutput = sourceOutput
        self.writerRecord = writerRecord
        self.providerRecord = providerRecord
        self.providerOutput = providerOutput
        self.sourceArtifact = sourceArtifact
        self.providerArtifact = providerArtifact
        self.sourceContext = sourceContext
        self.recordingDevice = recordingDevice
        self.deviceSnapshot = deviceSnapshot
        self.event = event
        self.entryNode = entryNode
    }

    /// The systems in the exchange protocol's recommended form under one deployment root: twelve distinct forms, so
    /// twelve distinct systems.
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
        return Self(
            sourceRecord: try system(form, kind: .sourceRecord),
            sourceOutput: try system(form, kind: .sourceOutput),
            writerRecord: try system(form, kind: .writerRecord),
            providerRecord: try system(form, kind: .providerRecord),
            providerOutput: try system(form, kind: .providerOutput),
            sourceArtifact: try system(form, kind: .sourceArtifact),
            providerArtifact: try system(form, kind: .providerArtifact),
            sourceContext: try system(form, kind: .sourceContext),
            recordingDevice: try system(form, kind: .recordingDevice),
            deviceSnapshot: try system(form, kind: .deviceSnapshot),
            event: try system(ExchangeContract.eventIdentifierSystemForm),
            entryNode: try system(ExchangeContract.entryNodeIdentifierSystemForm)
        )
    }

    /// The system of one opaque identity kind.
    package subscript(kind: OpaqueIdentityKind) -> IdentifierSystem {
        switch kind {
        case .sourceRecord: sourceRecord
        case .sourceOutput: sourceOutput
        case .writerRecord: writerRecord
        case .providerRecord: providerRecord
        case .providerOutput: providerOutput
        case .sourceArtifact: sourceArtifact
        case .providerArtifact: providerArtifact
        case .sourceContext: sourceContext
        case .recordingDevice: recordingDevice
        case .deviceSnapshot: deviceSnapshot
        }
    }
}
