//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Complete business identities of one emitted exchange graph.
public struct ExchangeGraphIdentifiers: Hashable, Sendable {
    public let event: RoledIdentifier
    public let sourceRecord: RoledIdentifier
    public let primaryOutput: RoledIdentifier
    public let applicationSnapshot: RoledIdentifier
    public let hostSnapshot: RoledIdentifier
    public let provenance: RoledIdentifier
    public let childOutputs: [RoledIdentifier]
    public let sourceArtifact: RoledIdentifier?
    public let recordingDeviceSnapshot: RoledIdentifier?
    public let sourceAuthorSnapshot: RoledIdentifier?
    public let sourceAuthorHostSnapshot: RoledIdentifier?

    public init(
        event: RoledIdentifier,
        sourceRecord: RoledIdentifier,
        primaryOutput: RoledIdentifier,
        applicationSnapshot: RoledIdentifier,
        hostSnapshot: RoledIdentifier,
        provenance: RoledIdentifier,
        childOutputs: [RoledIdentifier] = [],
        sourceArtifact: RoledIdentifier? = nil,
        recordingDeviceSnapshot: RoledIdentifier? = nil,
        sourceAuthorSnapshot: RoledIdentifier? = nil,
        sourceAuthorHostSnapshot: RoledIdentifier? = nil
    ) {
        self.event = event
        self.sourceRecord = sourceRecord
        self.primaryOutput = primaryOutput
        self.applicationSnapshot = applicationSnapshot
        self.hostSnapshot = hostSnapshot
        self.provenance = provenance
        self.childOutputs = childOutputs
        self.sourceArtifact = sourceArtifact
        self.recordingDeviceSnapshot = recordingDeviceSnapshot
        self.sourceAuthorSnapshot = sourceAuthorSnapshot
        self.sourceAuthorHostSnapshot = sourceAuthorHostSnapshot
    }
}
