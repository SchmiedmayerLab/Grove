//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@_spi(TestingSupport)
import GroveBluetooth
import GroveBluetoothServices
@_spi(TestingSupport)
@testable import GroveDevices
import HealthKit
import Testing


@MainActor
@Suite
struct HealthMeasurementsTests {
    @Test
    func receivingWeightMeasurements() async throws {
        let device = MockDevice.createMockDevice(state: .connecting, weightMeasurement: .mock(additionalInfo: .init(bmi: 230, height: 1790)))
        let measurements = HealthMeasurements()

        measurements.configureReceivingMeasurements(for: device, on: \.weightScale)

        // just inject the same value again to trigger on change!
        let measurement = try #require(device.weightScale.weightMeasurement)
        device.weightScale.$weightMeasurement.inject(measurement) // first measurement should be ignored in connecting state!

        try await Task.sleep(for: .milliseconds(50))
        device.$state.inject(.connected)
        device.weightScale.$weightMeasurement.inject(measurement)

        try await Task.sleep(for: .milliseconds(50))

        #expect(measurements.shouldPresentMeasurements)
        #expect(measurements.pendingMeasurements.count == 1)

        let weightMeasurement = try #require(measurements.pendingMeasurements.first)
        guard case let .weight(sample, bmi0, height0) = weightMeasurement else {
            Issue.record("Unexpected type of measurement: \(weightMeasurement)")
            return
        }

        let bmi = try #require(bmi0)
        let height = try #require(height0)
        let expectedDate = try #require(device.weightScale.weightMeasurement?.timeStamp?.date)

        #expect(weightMeasurement.samples == [sample, bmi, height])

        #expect(sample.quantityType == HKQuantityType(.bodyMass))
        #expect(sample.startDate == expectedDate)
        #expect(sample.endDate == sample.startDate)
        #expect(sample.quantity.doubleValue(for: .gramUnit(with: .kilo)) == 42.0)
        #expect(sample.device?.name == "Mock Device")


        #expect(bmi.quantityType == HKQuantityType(.bodyMassIndex))
        #expect(bmi.startDate == expectedDate)
        #expect(bmi.endDate == sample.startDate)
        #expect(bmi.quantity.doubleValue(for: .count()) == 23)
        #expect(bmi.device?.name == "Mock Device")

        #expect(height.quantityType == HKQuantityType(.height))
        #expect(height.startDate == expectedDate)
        #expect(height.endDate == sample.startDate)
        #expect(height.quantity.doubleValue(for: .meterUnit(with: .centi)) == 179.0)
        #expect(height.device?.name == "Mock Device")
    }

    @Test
    func receivingBloodPressureMeasurements() async throws {
        let device = MockDevice.createMockDevice(state: .connected)
        let measurements = HealthMeasurements()

        measurements.configureReceivingMeasurements(for: device, on: \.bloodPressure)

        // just inject the same value again to trigger on change!
        let measurement = try #require(device.bloodPressure.bloodPressureMeasurement)
        device.bloodPressure.$bloodPressureMeasurement.inject(measurement)

        try await Task.sleep(for: .milliseconds(50))

        #expect(measurements.shouldPresentMeasurements)
        #expect(measurements.pendingMeasurements.count == 1)

        let bloodPressureMeasurement = try #require(measurements.pendingMeasurements.first)
        guard case let .bloodPressure(sample, heartRate0) = bloodPressureMeasurement else {
            Issue.record("Unexpected type of measurement: \(bloodPressureMeasurement)")
            return
        }

        let heartRate = try #require(heartRate0)
        let expectedDate = try #require(device.weightScale.weightMeasurement?.timeStamp?.date)

        #expect(bloodPressureMeasurement.samples == [sample, heartRate])


        #expect(heartRate.quantityType == HKQuantityType(.heartRate))
        #expect(heartRate.startDate == expectedDate)
        #expect(heartRate.endDate == sample.startDate)
        #expect(heartRate.quantity.doubleValue(for: .count().unitDivided(by: .minute())) == 62)
        #expect(heartRate.device?.name == "Mock Device")

        #expect(sample.objects.count == 2)
        let systolic = try #require(sample.objects(for: HKQuantityType(.bloodPressureSystolic)).first as? HKQuantitySample)
        let diastolic = try #require(sample.objects(for: HKQuantityType(.bloodPressureDiastolic)).first as? HKQuantitySample)

        #expect(systolic.quantityType == HKQuantityType(.bloodPressureSystolic))
        #expect(systolic.startDate == expectedDate)
        #expect(systolic.endDate == sample.startDate)
        #expect(systolic.quantity.doubleValue(for: .millimeterOfMercury()) == 103.0)
        #expect(systolic.device?.name == "Mock Device")

        #expect(diastolic.quantityType == HKQuantityType(.bloodPressureDiastolic))
        #expect(diastolic.startDate == expectedDate)
        #expect(diastolic.endDate == sample.startDate)
        #expect(diastolic.quantity.doubleValue(for: .millimeterOfMercury()) == 64.0)
        #expect(diastolic.device?.name == "Mock Device")
    }

    @Test
    func measurementStorage() async throws {
        let measurements = HealthMeasurements()

        measurements.configure(inMemoryStorage: true) // init model container
        await measurements.run() // load measurements

        measurements.loadMockWeightMeasurement()
        measurements.loadMockBloodPressureMeasurement()

        #expect(measurements.pendingMeasurements.count == 2)

        try measurements.refreshFetchingMeasurements() // clear pending measurements and fetch again from storage
        try await Task.sleep(for: .milliseconds(50))

        #expect(measurements.pendingMeasurements.count == 2)
        // tests that order stays same over storage retrieval

        // Restoring from disk doesn't preserve HealthKit UUIDs
        guard case .bloodPressure = measurements.pendingMeasurements.first,
              case .weight = measurements.pendingMeasurements.last else {
            Issue.record("Order of measurements doesn't match: \(measurements.pendingMeasurements)")
            return
        }
    }

    @Test
    func discardingMeasurements() async throws {
        let device = MockDevice.createMockDevice(state: .connected)
        let measurements = HealthMeasurements()

        measurements.configureReceivingMeasurements(for: device, on: \.bloodPressure)
        measurements.configureReceivingMeasurements(for: device, on: \.weightScale)

        let measurement1 = try #require(device.weightScale.weightMeasurement)
        device.weightScale.$weightMeasurement.inject(measurement1)

        try await Task.sleep(for: .milliseconds(50))

        let measurement0 = try #require(device.bloodPressure.bloodPressureMeasurement)
        device.bloodPressure.$bloodPressureMeasurement.inject(measurement0)

        try await Task.sleep(for: .milliseconds(50))

        #expect(measurements.shouldPresentMeasurements)
        #expect(measurements.pendingMeasurements.count == 2)

        let bloodPressureMeasurement = try #require(measurements.pendingMeasurements.first)

        // measurements are prepended
        guard case .bloodPressure = bloodPressureMeasurement else {
            Issue.record("Unexpected type of measurement: \(bloodPressureMeasurement)")
            return
        }

        measurements.discardMeasurement(bloodPressureMeasurement)
        #expect(measurements.shouldPresentMeasurements)
        #expect(measurements.pendingMeasurements.count == 1)

        let weightMeasurement = try #require(measurements.pendingMeasurements.first)
        guard case .weight = weightMeasurement else {
            Issue.record("Unexpected type of measurement: \(weightMeasurement)")
            return
        }
    }

    @Test
    func bluetoothMeasurementCodable() throws { // swiftlint:disable:this function_body_length
        let weightMeasurement =
            """
            {
                "type": "weight",
                "measurement": {"weight":8400, "unit":"si", "timeStamp":{"minutes":33,"day":5,"year":2024,"hours":12,"seconds":11,"month":6}},
                "features": 6
            }

            """
        let bloodPressureMeasurement =
            """
            {
                "type":"bloodPressure",
                "measurement":{
                    "unit":"mmHg",
                    "systolicValue":62470,
                    "diastolicValue":62080,
                    "timeStamp":{"seconds":11,"day":5,"hours":12,"year":2024,"month":6,"minutes":33},
                    "meanArterialPressure":62210,
                    "pulseRate":62060,
                    "measurementStatus":0,
                    "userId":1
                },
                "features":257
            }

            """

        let decoder = JSONDecoder()

        let weightData = try #require(weightMeasurement.data(using: .utf8))
        let pressureData = try #require(bloodPressureMeasurement.data(using: .utf8))

        let decodedWeight = try decoder.decode(BluetoothHealthMeasurement.self, from: weightData)
        let decodedPressure = try decoder.decode(BluetoothHealthMeasurement.self, from: pressureData)

        let dateTime = DateTime(year: 2024, month: .june, day: 5, hours: 12, minutes: 33, seconds: 11)
        #expect(
            decodedWeight ==
            .weight(.init(weight: 8400, unit: .si, timeStamp: dateTime), [.bmiSupported, .multipleUsersSupported])
        )

        #expect(
            decodedPressure ==
            .bloodPressure(
                .init(
                    systolic: 103,
                    diastolic: 64,
                    meanArterialPressure: 77,
                    unit: .mmHg,
                    timeStamp: dateTime,
                    pulseRate: 62,
                    userId: 1,
                    measurementStatus: []
                ),
                [.bodyMovementDetectionSupported, .userFacingTimeSupported]
            )
        )
    }
}
