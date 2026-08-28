//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


#if canImport(HealthKit)

import Foundation


/// Event-time facts about the host on which a HealthKit conversion runs.
///
/// This is deliberately separate from ``HealthKitApplication``. An application release and its
/// host operating system have different lifecycles, and FHIR represents them as two Device
/// snapshots connected through `Device.parent`.
public struct HealthKitHostDevice: Hashable, Sendable {
    /// A snapshot of the current host.
    ///
    /// Capture and persist this value with the exchange event. Reconstructing it during a later
    /// retry after an operating-system update would describe a different snapshot.
    public static var current: HealthKitHostDevice {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return HealthKitHostDevice(
            sourceDeviceToken: "current-converter-host",
            operatingSystemVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        )
    }

    /// Event-local source token used only inside the keyed snapshot identity preimage.
    ///
    /// It is never emitted verbatim and makes two hosts in the same event distinguishable. This
    /// is not a stable physical-device identifier; a host Device is an immutable event snapshot.
    public let sourceDeviceToken: String
    public let operatingSystemVersion: String
    public let name: String?
    public let manufacturer: String?
    public let modelNumber: String?

    public init(
        sourceDeviceToken: String,
        operatingSystemVersion: String,
        name: String? = nil,
        manufacturer: String? = nil,
        modelNumber: String? = nil
    ) {
        self.sourceDeviceToken = sourceDeviceToken
        self.operatingSystemVersion = operatingSystemVersion
        self.name = name
        self.manufacturer = manufacturer
        self.modelNumber = modelNumber
    }
}

#endif
