//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// The hardware that acquired a record: every fact its source states about it, and the unit it is when that is known.
///
/// A record names a recording Device whenever its source names the hardware; a Device needs no stable unit token. The
/// Device states every fact set here, each as the adapter's catalog maps it, and its content snapshot covers them all.
/// Equal facts never prove one physical unit: only ``stableUnitToken`` does. A blank fact counts as unset.
public struct RecordingDevice: Hashable, Sendable {
    /// A verified per-unit token. It is never emitted: it enters the deployment-scoped `recording-device` identity, and
    /// needs ``tokenScope`` to do so.
    public var stableUnitToken: String?
    /// The authority that assigned ``stableUnitToken``, such as the writer's `HKSource.bundleIdentifier`: a platform's unit
    /// token can be local to its host, so the same value from two writers names two units.
    public var tokenScope: String?
    /// The name a person gave the device, which may name that person.
    public var name: String?
    public var manufacturer: String?
    /// The model the source states. `Device.modelNumber` states it unless ``productType`` does; then it is the device's
    /// model name.
    public var model: String?
    /// The hardware product type, such as `Watch7,1`.
    public var productType: String?
    public var systemName: String?
    public var systemVersion: String?
    public var hardwareVersion: String?
    public var firmwareVersion: String?
    public var softwareVersion: String?
    /// The clear identifier the source states for the device, carried as a `Device.identifier` under the deployment's
    /// ``DeploymentIdentifierSystems/deviceLocalIdentifier`` system. It is local to the host that recorded it, so equal
    /// values never prove one unit.
    public var localIdentifier: String?
    public var udiDeviceIdentifier: String?
    /// The raw UDI production identifier, which may embed a lot or serial number.
    public var udiProductionIdentifier: String?
    /// A serial number, which links globally.
    public var serialNumber: String?

    public init() {}
}
