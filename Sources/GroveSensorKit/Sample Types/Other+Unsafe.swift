//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@preconcurrency public import SensorKit

// Note: all of the types below are types which techncally aren't Sendable, but for which we don't yet have a custom representation.
// We use the @preconcurrency import to make it work anyway, for the time being.


extension SRKeyboardMetrics: SensorKitSampleProtocol {
    public typealias SafeRepresentation = DefaultSensorKitSampleSafeRepresentation<SRKeyboardMetrics>
}
