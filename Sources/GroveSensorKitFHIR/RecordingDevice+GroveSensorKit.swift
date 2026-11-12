//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)

public import GroveFHIRContract
public import GroveSensorKit


@available(iOS 18, *)
extension RecordingDevice {
    /// The recording Device of the `SRDevice` that recorded a batch, stating every fact SensorKit exposes for it.
    ///
    /// `SRDevice.name` is the name a person gave the device; keep it out of logs and upload metadata.
    public init(_ info: SensorKit.DeviceInfo) {
        self.init()
        name = info.name
        model = info.model
        systemName = info.systemName
        systemVersion = info.systemVersion
        productType = info.productType
    }

    /// The recording Device of a peripheral that supplied a batch, stating every fact `SRSourceDevice` exposes.
    ///
    /// Its local identifier travels clear; it is local to one host and proves no physical unit.
    public init(_ info: SensorKit.SourceDeviceInfo) {
        self.init()
        localIdentifier = info.localIdentifier
        manufacturer = info.manufacturer
        model = info.model
        hardwareVersion = info.hardwareVersion
        firmwareVersion = info.firmwareVersion
    }
}

#endif
