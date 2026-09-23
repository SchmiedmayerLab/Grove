//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

extension OpaqueIdentityScope {
    /// Identifies one physical acquisition unit for one subject by its governed stable per-unit token.
    public func recordingDevice(
        adapterID: String,
        subject: BusinessIdentifier,
        stableUnitToken: String
    ) throws(OpaqueIdentityError) -> RoledIdentifier {
        try identifier(
            kind: .recordingDevice,
            components: [
                adapterID,
                subject.system.rawValue,
                subject.value,
                stableUnitToken
            ]
        )
    }

    /// Identifies one immutable event-time Device snapshot, the snapshot's Bundle entry key.
    public func deviceSnapshot(
        event: ExchangeEventIdentifier,
        role: DeviceSnapshotRole,
        sourceDeviceToken: String
    ) throws(OpaqueIdentityError) -> RoledIdentifier {
        try identifier(
            kind: .deviceSnapshot,
            components: [
                event.identifier.identifier.system.rawValue,
                event.identifier.identifier.value,
                role.rawValue,
                sourceDeviceToken
            ]
        )
    }
}
