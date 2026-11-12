//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// All thirteen identifier systems a deployment owns for its opaque identities, one per kind, and the one its clear
/// device identifiers travel under.
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
    public let contextSnapshot: IdentifierSystem
    public let recordVersion: IdentifierSystem
    public let recordRetraction: IdentifierSystem
    /// The system of the clear identifier a source states for a recording Device.
    ///
    /// Its values are the source's own, not keyed, so it names no key id or epoch.
    public let deviceLocalIdentifier: IdentifierSystem

    /// Every system the deployment reserves for its graph identities: each opaque kind's, derived from the closed kind
    /// list so a new kind cannot slip past a privacy check.
    package var all: [IdentifierSystem] {
        OpaqueIdentityKind.allCases.map { self[$0] }
    }

    /// The systems as stated. ``derived(root:keyID:epoch:)``, the only public way to form them, yields distinct systems
    /// by construction; a test that states its own keeps them distinct.
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
        contextSnapshot: IdentifierSystem,
        recordVersion: IdentifierSystem,
        recordRetraction: IdentifierSystem,
        deviceLocalIdentifier: IdentifierSystem
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
        self.contextSnapshot = contextSnapshot
        self.recordVersion = recordVersion
        self.recordRetraction = recordRetraction
        self.deviceLocalIdentifier = deviceLocalIdentifier
    }

    /// The systems in the exchange protocol's recommended form under one deployment root: distinct forms, so distinct
    /// systems.
    ///
    /// A rotated key uses a new key id or epoch, and with them new opaque systems.
    public static func derived(
        root: IdentifierSystem,
        keyID: String,
        epoch: KeyEpoch
    ) throws(ExchangeIdentityError) -> Self {
        guard OpaqueIdentityScope.isValidKeyID(keyID) else {
            throw .invalidKeyID(keyID)
        }
        let deploymentRoot = root.rawValue.hasSuffix("/") ? String(root.rawValue.dropLast()) : root.rawValue
        func system(_ kind: OpaqueIdentityKind) throws(ExchangeIdentityError) -> IdentifierSystem {
            let text = ExchangeContract.opaqueIdentitySystemForm
                .replacingOccurrences(of: "<deployment-root>", with: deploymentRoot)
                .replacingOccurrences(of: "<identity-kind>", with: kind.rawValue)
                .replacingOccurrences(of: "<key-id>", with: keyID)
                .replacingOccurrences(of: "<epoch>", with: epoch.rawValue)
            return try IdentifierSystem(text)
        }
        return Self(
            sourceRecord: try system(.sourceRecord),
            sourceOutput: try system(.sourceOutput),
            writerRecord: try system(.writerRecord),
            providerRecord: try system(.providerRecord),
            providerOutput: try system(.providerOutput),
            sourceArtifact: try system(.sourceArtifact),
            providerArtifact: try system(.providerArtifact),
            sourceContext: try system(.sourceContext),
            recordingDevice: try system(.recordingDevice),
            deviceSnapshot: try system(.deviceSnapshot),
            contextSnapshot: try system(.contextSnapshot),
            recordVersion: try system(.recordVersion),
            recordRetraction: try system(.recordRetraction),
            deviceLocalIdentifier: try IdentifierSystem("\(deploymentRoot)/NamingSystem/grove-device-local-identifier")
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
        case .contextSnapshot: contextSnapshot
        case .recordVersion: recordVersion
        case .recordRetraction: recordRetraction
        }
    }
}
