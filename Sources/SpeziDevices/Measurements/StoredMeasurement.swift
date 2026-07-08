//
// This source file is part of the Stanford SpeziDevices open source project
//
// SPDX-FileCopyrightText: 2024 Stanford University
//
// SPDX-License-Identifier: MIT
//


import HealthKit
import SpeziBluetoothServices
import SpeziNumerics
import SwiftData


private struct CodableHKDevice {
    let name: String?
    let manufacturer: String?
    let model: String?
    let hardwareVersion: String?
    let firmwareVersion: String?
    let softwareVersion: String?
    let localIdentifier: String?
    let udiDeviceIdentifier: String?
}


/// Copy of the `BloodPressureMeasurement` type that just uses plain RawValue types to work around SwiftData coding issues and crashes.
private struct BloodPressureMeasurementSwiftDataWorkaroundContainer { // swiftlint:disable:this type_name
    let systolicValue: UInt16
    let diastolicValue: UInt16
    let meanArterialPressure: UInt16
    let unit: String


    let timeStamp: DateTime?
    let pulseRate: UInt16?

    let userId: UInt8?
    let measurementStatus: UInt16?


    var measurement: BloodPressureMeasurement {
        .init(
            systolic: MedFloat16(bitPattern: systolicValue),
            diastolic: MedFloat16(bitPattern: diastolicValue),
            meanArterialPressure: MedFloat16(bitPattern: meanArterialPressure),
            unit: .init(rawValue: unit) ?? .mmHg,
            timeStamp: timeStamp,
            pulseRate: pulseRate.map { MedFloat16(bitPattern: $0) },
            userId: userId,
            measurementStatus: measurementStatus.map { .init(rawValue: $0) }
        )
    }

    init(from measurement: BloodPressureMeasurement) {
        self.systolicValue = measurement.systolicValue.rawValue
        self.diastolicValue = measurement.diastolicValue.rawValue
        self.meanArterialPressure = measurement.meanArterialPressure.rawValue
        self.unit = measurement.unit.rawValue
        self.timeStamp = measurement.timeStamp
        self.pulseRate = measurement.pulseRate?.rawValue
        self.userId = measurement.userId
        self.measurementStatus = measurement.measurementStatus?.rawValue
    }
}


private struct WeightMeasurementSwiftDataWorkaroundContainer { // swiftlint:disable:this type_name
    let weight: UInt16
    let unit: String
    
    let timestamp: DateTime?
    
    let userId: UInt8?
    let bmi: UInt16?
    let height: UInt16?

    var measurement: WeightMeasurement {
        var info: WeightMeasurement.AdditionalInfo?
        if let bmi, let height {
            info = .init(bmi: bmi, height: height)
        }

        return WeightMeasurement(
            weight: weight,
            unit: .init(rawValue: unit) ?? .si,
            timeStamp: timestamp,
            userId: userId,
            additionalInfo: info
        )
    }

    init(from measurement: WeightMeasurement) {
        self.weight = measurement.weight
        self.unit = measurement.unit.rawValue
        self.timestamp = measurement.timeStamp
        self.userId = measurement.userId
        self.bmi = measurement.additionalInfo?.bmi
        self.height = measurement.additionalInfo?.height
    }
}


// swiftlint:disable:next type_name
private struct SwiftDataBluetoothHealthMeasurementWorkaroundContainer {
    enum MeasurementType: String, Codable {
        case weight
        case bloodPressure
    }

    private let type: MeasurementType

    private var bloodPressureMeasurement: BloodPressureMeasurementSwiftDataWorkaroundContainer?
    private var bloodPressureFeatures: BloodPressureFeature.RawValue?

    private var weightMeasurement: WeightMeasurementSwiftDataWorkaroundContainer?
    private var weightScaleFeatures: WeightScaleFeature.RawValue?

    var measurement: BluetoothHealthMeasurement {
        switch type {
        case .bloodPressure:
            guard let bloodPressureMeasurement, let bloodPressureFeatures else {
                preconditionFailure("Inconsistent type")
            }
            return .bloodPressure(bloodPressureMeasurement.measurement, .init(rawValue: bloodPressureFeatures))
        case .weight:
            guard let weightMeasurement, let weightScaleFeatures else {
                preconditionFailure("Inconsistent type")
            }
            return .weight(weightMeasurement.measurement, .init(rawValue: weightScaleFeatures))
        }
    }

    init(from measurement: BluetoothHealthMeasurement) {
        switch measurement {
        case let .bloodPressure(measurement, feature):
            type = .bloodPressure
            bloodPressureMeasurement = .init(from: measurement)
            bloodPressureFeatures = feature.rawValue
            weightMeasurement = nil
            weightScaleFeatures = nil
        case let .weight(measurement, features):
            type = .weight
            bloodPressureMeasurement = nil
            bloodPressureFeatures = nil
            weightMeasurement = .init(from: measurement)
            weightScaleFeatures = features.rawValue
        }
    }
}

@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
@Model
final class StoredMeasurement {
    @Attribute(.unique)
    var associatedMeasurement: UUID

    private var measurement: SwiftDataBluetoothHealthMeasurementWorkaroundContainer
    fileprivate var codableDevice: CodableHKDevice

    var storageDate: Date

    var device: HKDevice {
        codableDevice.hkDevice
    }

    var healthMeasurement: BluetoothHealthMeasurement {
        measurement.measurement
    }

    init(associatedMeasurement: UUID, measurement: BluetoothHealthMeasurement, device: HKDevice) {
        self.associatedMeasurement = associatedMeasurement
        self.measurement = .init(from: measurement)
        self.codableDevice = CodableHKDevice(from: device)
        self.storageDate = .now
    }
}


extension CodableHKDevice: Codable {}


@available(macOS 13.0, *)
extension CodableHKDevice {
    var hkDevice: HKDevice {
        HKDevice(
            name: name,
            manufacturer: manufacturer,
            model: model,
            hardwareVersion: hardwareVersion,
            firmwareVersion: firmwareVersion,
            softwareVersion: softwareVersion,
            localIdentifier: localIdentifier,
            udiDeviceIdentifier: udiDeviceIdentifier
        )
    }

    init(from hkDevice: HKDevice) {
        self.name = hkDevice.name
        self.manufacturer = hkDevice.manufacturer
        self.model = hkDevice.model
        self.hardwareVersion = hkDevice.hardwareVersion
        self.firmwareVersion = hkDevice.firmwareVersion
        self.softwareVersion = hkDevice.softwareVersion
        self.localIdentifier = hkDevice.localIdentifier
        self.udiDeviceIdentifier = hkDevice.udiDeviceIdentifier
    }
}


extension BloodPressureMeasurementSwiftDataWorkaroundContainer: Codable {
    enum CodingKeys: CodingKey {
        case systolicValue
        case diastolicValue
        case meanArterialPressure
        case unit
        case timeStamp
        case pulseRate
        case userId
        case measurementStatus
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.systolicValue = try container.decode(UInt16.self, forKey: .systolicValue)
        self.diastolicValue = try container.decode(UInt16.self, forKey: .diastolicValue)
        self.meanArterialPressure = try container.decode(UInt16.self, forKey: .meanArterialPressure)
        self.unit = try container.decode(String.self, forKey: .unit)
        self.timeStamp = try container.decodeIfPresent(DateTime.self, forKey: .timeStamp)
        self.pulseRate = try container.decodeIfPresent(UInt16.self, forKey: .pulseRate)
        self.userId = try container.decodeIfPresent(UInt8.self, forKey: .userId)
        self.measurementStatus = try container.decodeIfPresent(UInt16.self, forKey: .measurementStatus)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.systolicValue, forKey: .systolicValue)
        try container.encode(self.diastolicValue, forKey: .diastolicValue)
        try container.encode(self.meanArterialPressure, forKey: .meanArterialPressure)
        try container.encode(self.unit, forKey: .unit)
        try container.encodeIfPresent(self.timeStamp, forKey: .timeStamp)
        try container.encodeIfPresent(self.pulseRate, forKey: .pulseRate)
        try container.encodeIfPresent(self.userId, forKey: .userId)
        try container.encodeIfPresent(self.measurementStatus, forKey: .measurementStatus)
    }
}


extension WeightMeasurementSwiftDataWorkaroundContainer: Codable {
    enum CodingKeys: CodingKey {
        case weight
        case unit
        case timestamp
        case userId
        case bmi
        case height
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.weight = try container.decode(UInt16.self, forKey: .weight)
        self.unit = try container.decode(String.self, forKey: .unit)
        self.timestamp = try container.decodeIfPresent(DateTime.self, forKey: .timestamp)
        self.userId = try container.decodeIfPresent(UInt8.self, forKey: .userId)
        self.bmi = try container.decodeIfPresent(UInt16.self, forKey: .bmi)
        self.height = try container.decodeIfPresent(UInt16.self, forKey: .height)
    }


    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.weight, forKey: .weight)
        try container.encode(self.unit, forKey: .unit)
        try container.encodeIfPresent(self.timestamp, forKey: .timestamp)
        try container.encodeIfPresent(self.userId, forKey: .userId)
        try container.encodeIfPresent(self.bmi, forKey: .bmi)
        try container.encodeIfPresent(self.height, forKey: .height)
    }
}


extension SwiftDataBluetoothHealthMeasurementWorkaroundContainer: Codable {
    enum CodingKeys: CodingKey {
        case type
        case bloodPressureMeasurement
        case bloodPressureFeatures
        case weightMeasurement
        case weightScaleFeatures
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(SwiftDataBluetoothHealthMeasurementWorkaroundContainer.MeasurementType.self, forKey: .type)
        switch type {
        case .bloodPressure:
            self.bloodPressureMeasurement = try container.decodeIfPresent(
                BloodPressureMeasurementSwiftDataWorkaroundContainer.self,
                forKey: .bloodPressureMeasurement
            )
            self.bloodPressureFeatures = try container.decodeIfPresent(BloodPressureFeature.RawValue.self, forKey: .bloodPressureFeatures)
        case .weight:
            self.weightMeasurement = try container.decodeIfPresent(WeightMeasurementSwiftDataWorkaroundContainer.self, forKey: .weightMeasurement)
            self.weightScaleFeatures = try container.decodeIfPresent(WeightScaleFeature.RawValue.self, forKey: .weightScaleFeatures)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.type, forKey: .type)
        try container.encodeIfPresent(self.bloodPressureMeasurement, forKey: .bloodPressureMeasurement)
        try container.encodeIfPresent(self.bloodPressureFeatures, forKey: .bloodPressureFeatures)
        try container.encodeIfPresent(self.weightMeasurement, forKey: .weightMeasurement)
        try container.encodeIfPresent(self.weightScaleFeatures, forKey: .weightScaleFeatures)
    }
}
