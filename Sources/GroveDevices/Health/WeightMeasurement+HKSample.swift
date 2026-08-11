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
extension WeightMeasurement {
    /// Convert the weight measurement to the HealthKit representation.
    ///
    /// Converts the weight measurement to a `HKQuantitySample`.
    /// - Parameters:
    ///   - device: The device information to reference with the `HKQuantitySample`.
    ///     You may use ``HealthDevice/hkDevice`` to retrieve the device information from a ``HealthDevice``.
    ///   - resolution: The resolution provided by the `WeightScaleFeature` characteristic. Otherwise, assumes default resolution.
    /// - Returns: Returns the `HKQuantitySample` with the weight value.
    public func weightSample(source device: HKDevice?, resolution: WeightScaleFeature.WeightResolution = .unspecified) -> HKQuantitySample {
        let value = weight(of: resolution)

        let quantityType = HKQuantityType(.bodyMass)
        let quantity = HKQuantity(unit: unit.massUnit, doubleValue: value)
        let date = timeStamp?.date ?? .now

        return HKQuantitySample(
            type: quantityType,
            quantity: quantity,
            start: date,
            end: date,
            device: device,
            metadata: nil
        )
    }

    /// Convert the BMI measurement to the HealthKit representation.
    ///
    /// Converts the BMI measurement to a `HKQuantitySample`.
    /// - Parameter device: The device information to reference with the `HKQuantitySample`.
    ///     You may use ``HealthDevice/hkDevice`` to retrieve the device information from a ``HealthDevice``.
    /// - Returns: Returns the `HKQuantitySample` with the BMI value. Returns `nil` if the measurement didn't contain a BMI value.
    public func bmiSample(source device: HKDevice?) -> HKQuantitySample? {
        guard let bmi = additionalInfo?.bmi else {
            return nil
        }

        // `bmi` is in units of 0.1 kg/m2
        let bmiValue = Double(bmi) * 0.1

        let unit: HKUnit = .count() // HealthKit uses count unit for BMI
        let quantityType = HKQuantityType(.bodyMassIndex)
        let quantity = HKQuantity(unit: unit, doubleValue: bmiValue)

        let date = timeStamp?.date ?? .now

        return HKQuantitySample(type: quantityType, quantity: quantity, start: date, end: date, device: device, metadata: nil)
    }

    /// Convert the height measurement to the HealthKit representation.
    ///
    /// Converts the height measurement to a `HKQuantitySample`.
    /// - Parameters:
    ///   - device: The device information to reference with the `HKQuantitySample`.
    ///     You may use ``HealthDevice/hkDevice`` to retrieve the device information from a ``HealthDevice``.
    ///   - resolution: The resolution provided by the `WeightScaleFeature` characteristic. Otherwise, assumes default resolution.
    /// - Returns: Returns the `HKQuantitySample` with the height value. Returns `nil` if the measurement didn't contain a height value.
    public func heightSample(source device: HKDevice?, resolution: WeightScaleFeature.HeightResolution = .unspecified) -> HKQuantitySample? {
        guard let height = height(of: resolution) else {
            return nil
        }

        let quantityType = HKQuantityType(.height)
        let quantity = HKQuantity(unit: unit.lengthUnit, doubleValue: height)
        let date = timeStamp?.date ?? .now

        return HKQuantitySample(type: quantityType, quantity: quantity, start: date, end: date, device: device, metadata: nil)
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension HKQuantitySample {
    /// Retrieve a mock weight sample.
    @_spi(TestingSupport)
    public static var mockWeighSample: HKQuantitySample {
        let measurement = WeightMeasurement(weight: 8400, unit: .si)

        return measurement.weightSample(source: nil, resolution: .resolution5g)
    }

    /// Retrieve a mock bmi sample.
    @_spi(TestingSupport)
    public static var mockBmiSample: HKQuantitySample {
        let measurement = WeightMeasurement(weight: 8400, unit: .si, additionalInfo: .init(bmi: 230, height: 1750))
        guard let sample = measurement.bmiSample(source: nil) else {
            preconditionFailure("Mock sample was unexpectedly invalid!")
        }
        return sample
    }

    /// Retrieve a mock height sample:
    @_spi(TestingSupport)
    public static var mockHeightSample: HKQuantitySample {
        let measurement = WeightMeasurement(weight: 8400, unit: .si, additionalInfo: .init(bmi: 230, height: 1750))
        guard let sample = measurement.heightSample(source: nil, resolution: .resolution1mm) else {
            preconditionFailure("Mock sample was unexpectedly invalid!")
        }
        return sample
    }
}
