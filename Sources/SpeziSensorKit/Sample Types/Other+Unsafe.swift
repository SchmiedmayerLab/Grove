//
// This source file is part of the My Heart Counts iOS application based on the Stanford Spezi Template Application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

@preconcurrency public import SensorKit

// Note: all of the types below are types which techncally aren't Sendable, but for which we don't yet have a custom representation.
// We use the @preconcurrency import to make it work anyway, for the time being.


@available(iOS 17, *)
extension SRMessagesUsageReport: SensorKitSampleProtocol {
    public typealias SafeRepresentation = DefaultSensorKitSampleSafeRepresentation<SRMessagesUsageReport>
}


@available(iOS 17, *)
extension SRPhoneUsageReport: SensorKitSampleProtocol {
    public typealias SafeRepresentation = DefaultSensorKitSampleSafeRepresentation<SRPhoneUsageReport>
}


@available(iOS 17, *)
extension SRKeyboardMetrics: SensorKitSampleProtocol {
    public typealias SafeRepresentation = DefaultSensorKitSampleSafeRepresentation<SRKeyboardMetrics>
}
