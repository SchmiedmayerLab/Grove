//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// A semantic role carried in `Identifier.type` for Grove exchange identifiers.
public enum GroveIdentifierRole: String, CaseIterable, Hashable, Sendable {
    case sourceRecord = "source-record"
    case sourceOutput = "source-output"
    case writerRecord = "writer-record"
    case sourceArtifact = "source-artifact"
    case sourceContext = "source-context"
    case recordingDevice = "recording-device"
    case deviceSnapshot = "device-snapshot"
    case event
    case entryNode = "entry-node"
}


/// The providers admitted by the 0.6 identity protocol.
///
/// Provider-owned records use a provider identity kind. Rejecting these values from generic
/// `source-*` constructors prevents two names for the same provider preimage.
public enum GroveProviderCode: String, CaseIterable, Hashable, Sendable {
    case googleHealthAPI = "google-health-api"
    case oura
    case withings
}


/// The closed resource-kind role used by an immutable event-time Device snapshot.
public enum GroveDeviceSnapshotRole: String, CaseIterable, Hashable, Sendable {
    case application
    case host
    case recordingDevice = "recording-device"
}


/// The closed domain-separation token fed to the v2 HMAC preimage.
public enum PseudonymousIdentityKind: String, CaseIterable, Hashable, Sendable {
    case sourceRecord = "source-record"
    case sourceOutput = "source-output"
    case writerRecord = "writer-record"
    case providerRecord = "provider-record"
    case providerOutput = "provider-output"
    case sourceArtifact = "source-artifact"
    case providerArtifact = "provider-artifact"
    case sourceContext = "source-context"
    case recordingDevice = "recording-device"
    case deviceSnapshot = "device-snapshot"

    /// The frozen number of typed fields in this identity kind's protocol preimage.
    public var componentCount: Int {
        switch self {
        case .sourceRecord, .providerRecord, .sourceContext: 5
        case .sourceOutput, .providerOutput, .sourceArtifact, .providerArtifact: 7
        case .writerRecord: 3
        case .recordingDevice, .deviceSnapshot: 4
        }
    }
}
