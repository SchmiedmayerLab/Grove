//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import GroveBluetoothServices


/// A measurement retrieved from a Bluetooth device.
///
/// Bluetooth Measurements are represented using standardized measurement characteristics.
public enum BluetoothHealthMeasurement {
    /// A weight measurement and its context.
    case weight(WeightMeasurement, WeightScaleFeature)
    /// A blood pressure measurement and its context.
    case bloodPressure(BloodPressureMeasurement, BloodPressureFeature)
}


extension BluetoothHealthMeasurement: Hashable, Sendable {}


extension BluetoothHealthMeasurement: Codable {
    enum MeasurementType: String, Codable {
        case weight
        case bloodPressure
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case measurement
        case features
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let type = try container.decode(MeasurementType.self, forKey: .type)
        switch type {
        case .weight:
            let measurement = try container.decode(WeightMeasurement.self, forKey: .measurement)
            let features = try container.decode(WeightScaleFeature.self, forKey: .features)
            self = .weight(measurement, features)
        case .bloodPressure:
            let measurement = try container.decode(BloodPressureMeasurement.self, forKey: .measurement)
            let features = try container.decode(BloodPressureFeature.self, forKey: .features)
            self = .bloodPressure(measurement, features)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .weight(measurement, feature):
            try container.encode(MeasurementType.weight, forKey: .type)
            try container.encode(measurement, forKey: .measurement)
            try container.encode(feature, forKey: .features)
        case let .bloodPressure(measurement, feature):
            try container.encode(MeasurementType.bloodPressure, forKey: .type)
            try container.encode(measurement, forKey: .measurement)
            try container.encode(feature, forKey: .features)
        }
    }
}
