//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Deployment-owned identifier systems for one key epoch.
///
/// A system names exactly one identity kind. Reusing one system across kinds makes rotation and
/// index policy ambiguous, so the initializer requires the complete closed set explicitly.
public struct PseudonymousIdentitySystems: Hashable, Sendable {
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

    public init(
        sourceRecord: IdentifierSystem,
        sourceOutput: IdentifierSystem,
        writerRecord: IdentifierSystem,
        providerRecord: IdentifierSystem,
        providerOutput: IdentifierSystem,
        sourceArtifact: IdentifierSystem,
        providerArtifact: IdentifierSystem,
        sourceContext: IdentifierSystem,
        recordingDevice: IdentifierSystem,
        deviceSnapshot: IdentifierSystem
    ) throws(PseudonymousIdentityError) {
        let values = [
            sourceRecord,
            sourceOutput,
            writerRecord,
            providerRecord,
            providerOutput,
            sourceArtifact,
            providerArtifact,
            sourceContext,
            recordingDevice,
            deviceSnapshot
        ]
        guard Set(values).count == values.count else {
            throw .reusedIdentifierSystem
        }
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
    }

    subscript(kind: PseudonymousIdentityKind) -> IdentifierSystem {
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
