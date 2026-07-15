//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import HealthKit
public import SpeziBluetoothServices


@available(iOS 18, macOS 15, watchOS 11, *)
extension BloodPressureMeasurement.Unit {
    /// The unit represented as a `HKUnit`.
    public var hkUnit: HKUnit {
        switch self {
        case .mmHg:
            return .millimeterOfMercury()
        case .kPa:
            return .pascalUnit(with: .kilo)
        }
    }
}
