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
extension BloodPressureMeasurement {
    /// Convert the blood pressure measurement to the HealthKit representation.
    ///
    /// Converts the content of the blood pressure measurement to a `HKCorrelation`.
    /// - Parameter device: The device information to reference with the `HKCorrelation`.
    ///     You may use ``HealthDevice/hkDevice`` to retrieve the device information from a ``HealthDevice``.
    /// - Returns: Returns the `HKCorrelation` with two samples for systolic and diastolic values. Returns `nil` if either of the blood pressure samples is non-finite.
    public func bloodPressureSample(source device: HKDevice?) -> HKCorrelation? {
        guard systolicValue.isFinite, diastolicValue.isFinite else {
            return nil
        }
        let unit: HKUnit = unit.hkUnit

        let systolic = HKQuantity(unit: unit, doubleValue: systolicValue.double)
        let diastolic = HKQuantity(unit: unit, doubleValue: diastolicValue.double)

        let systolicType = HKQuantityType(.bloodPressureSystolic)
        let diastolicType = HKQuantityType(.bloodPressureDiastolic)
        let correlationType = HKCorrelationType(.bloodPressure)

        let date = timeStamp?.date ?? .now

        let systolicSample = HKQuantitySample(type: systolicType, quantity: systolic, start: date, end: date, device: device, metadata: nil)
        let diastolicSample = HKQuantitySample(type: diastolicType, quantity: diastolic, start: date, end: date, device: device, metadata: nil)


        let bloodPressure = HKCorrelation(
            type: correlationType,
            start: date,
            end: date,
            objects: [systolicSample, diastolicSample],
            device: device,
            metadata: nil
        )

        return bloodPressure
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension BloodPressureMeasurement {
    /// Convert the heart rate measurement to the HealthKit representation.
    ///
    /// Converts the hear rate measurement of the blood pressure measurement to a `HKQuantitySample`.
    /// - Parameter device: The device information to reference with the `HKQuantitySample`.
    ///     You may use ``HealthDevice/hkDevice`` to retrieve the device information from a ``HealthDevice``.
    /// - Returns: Returns the `HKQuantitySample` with the heart rate value. Returns `nil` if no pulse rate is present or contains a non-finite value.
    public func heartRateSample(source device: HKDevice?) -> HKQuantitySample? {
        guard let pulseRate, pulseRate.isFinite else {
            return nil
        }

        // beats per minute
        let bpm: HKUnit = .count().unitDivided(by: .minute())
        let pulseQuantityType = HKQuantityType(.heartRate)

        let pulse = HKQuantity(unit: bpm, doubleValue: pulseRate.double)
        let date = timeStamp?.date ?? .now

        return HKQuantitySample(
            type: pulseQuantityType,
            quantity: pulse,
            start: date,
            end: date,
            device: device,
            metadata: nil
        )
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCorrelation {
    /// Retrieve a mock blood pressure sample.
    @_spi(TestingSupport)
    public static var mockBloodPressureSample: HKCorrelation {
        let dateTime = DateTime(from: .now)
        let measurement = BloodPressureMeasurement(
            systolic: 117,
            diastolic: 76,
            meanArterialPressure: 67,
            unit: .mmHg,
            timeStamp: dateTime,
            pulseRate: 68
        )
        guard let sample = measurement.bloodPressureSample(source: nil) else {
            preconditionFailure("Mock sample was unexpectedly invalid!")
        }
        return sample
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension HKQuantitySample {
    /// Retrieve a mock heart rate sample.
    @_spi(TestingSupport)
    public static var mockHeartRateSample: HKQuantitySample {
        let dateTime = DateTime(from: .now)
        let measurement = BloodPressureMeasurement(
            systolic: 117,
            diastolic: 76,
            meanArterialPressure: 67,
            unit: .mmHg,
            timeStamp: dateTime,
            pulseRate: 68
        )
        guard let sample = measurement.heartRateSample(source: nil) else {
            preconditionFailure("Mock sample was unexpectedly invalid!")
        }
        return sample
    }
}
