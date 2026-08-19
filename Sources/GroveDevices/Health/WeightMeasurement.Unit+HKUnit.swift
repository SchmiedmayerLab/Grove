//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


public import GroveBluetoothServices
public import HealthKit


@available(iOS 18, macOS 15, watchOS 11, *)
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
