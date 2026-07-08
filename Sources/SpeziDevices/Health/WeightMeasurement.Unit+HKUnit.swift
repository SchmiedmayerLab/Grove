//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


import HealthKit
import SpeziBluetoothServices


@available(macOS 13.0, *)
extension WeightMeasurement.Unit {
    /// The mass unit represented as a `HKUnit`.
    public var massUnit: HKUnit {
        switch self {
        case .si:
            return .gramUnit(with: .kilo)
        case .imperial:
            return .pound()
        }
    }


    /// The length unit represented as a `HKUnit`.
    public var lengthUnit: HKUnit {
        switch self {
        case .si:
            return .meter()
        case .imperial:
             return .inch()
        }
    }
}
