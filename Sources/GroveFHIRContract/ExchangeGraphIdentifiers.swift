//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Complete business identities of one emitted exchange graph.
package struct ExchangeGraphIdentifiers: Hashable, Sendable {
    package let event: RoledIdentifier
    package let sourceRecord: RoledIdentifier
    package let primaryOutput: RoledIdentifier
    package let applicationSnapshot: RoledIdentifier
    package let hostSnapshot: RoledIdentifier
    package let provenance: RoledIdentifier
    package let childOutputs: [RoledIdentifier]
    package let sourceArtifact: RoledIdentifier?
    package let recordingDeviceSnapshot: RoledIdentifier?
    package let writerSnapshot: RoledIdentifier?
    package let writerHostSnapshot: RoledIdentifier?

    package init(
        event: RoledIdentifier,
        sourceRecord: RoledIdentifier,
        primaryOutput: RoledIdentifier,
        applicationSnapshot: RoledIdentifier,
        hostSnapshot: RoledIdentifier,
        provenance: RoledIdentifier,
        childOutputs: [RoledIdentifier] = [],
        sourceArtifact: RoledIdentifier? = nil,
        recordingDeviceSnapshot: RoledIdentifier? = nil,
        writerSnapshot: RoledIdentifier? = nil,
        writerHostSnapshot: RoledIdentifier? = nil
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
        self.writerSnapshot = writerSnapshot
        self.writerHostSnapshot = writerHostSnapshot
    }
}
