//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
@_spi(TestingSupport)
public import GroveBluetooth
public import GroveBluetoothServices
public import GroveNumerics


@_spi(TestingSupport)
@available(iOS 18, macOS 15, watchOS 11, *)
public final class MockDevice: PairableDevice, HealthDevice, BatteryPoweredDevice, @unchecked Sendable {
    public static let appearance: DeviceAppearance = .appearance(Appearance(name: "My Mock Device"))

    @DeviceState(\.id)
    public var id
    @DeviceState(\.name)
    public var name
    @DeviceState(\.state)
    public var state
    @DeviceState(\.advertisementData)
    public var advertisementData
    @DeviceState(\.nearby)
    public var nearby

    @DeviceAction(\.connect)
    public var connect
    @DeviceAction(\.disconnect)
    public var disconnect


    @Service public var deviceInformation = DeviceInformationService()
    @Service public var battery = BatteryService()

    // Some mock health measurement services
    @Service public var bloodPressure = BloodPressureService()
    @Service public var weightScale = WeightScaleService()

    @Dependency(PairedDevices.self)
    private var pairedDevices: PairedDevices?

    public var isInPairingMode: Bool = false

    public init() {}


    public func configure() {
        $state.onChange { [weak self] state in
            self?.handleStateChange(state)
        }
    }


    fileprivate func handleStateChange(_ state: PeripheralState) {
        if isInPairingMode { // automatically respond to pairing event
            if case .connected = state {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))

                    guard case .connected = self.state else {
                        return
                    }
                    pairedDevices?.signalDevicePaired(self)
                }
            }
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension MockDevice {
    /// Create a new Mock Device instance.
    ///
    /// - Parameters:
    ///   - name: The name of the device.
    ///   - state: The initial peripheral state.
    ///   - nearby: The nearby state.
    ///   - bloodPressureMeasurement:  The blood pressure measurement loaded into the device.
    ///   - weightMeasurement: The weight measurement loaded into the device.
    ///   - weightResolution: The weight resolution to use.
    ///   - heightResolution: The height resolution to use.
    /// - Returns: Returns the initialized Mock Device.
    @_spi(TestingSupport)
    public static func createMockDevice(
        name: String = "Mock Device",
        state: PeripheralState = .disconnected,
        nearby: Bool = true,
        bloodPressureMeasurement: BloodPressureMeasurement = .mock(),
        weightMeasurement: WeightMeasurement = .mock(),
        weightResolution: WeightScaleFeature.WeightResolution = .resolution5g,
        heightResolution: WeightScaleFeature.HeightResolution = .resolution1mm
    ) -> MockDevice {
        let device = MockDevice()

        device.deviceInformation.$manufacturerName.inject("Mock Company")
        device.deviceInformation.$modelNumber.inject("MD1")
        device.deviceInformation.$hardwareRevision.inject("2")
        device.deviceInformation.$firmwareRevision.inject("1.0")

        device.battery.$batteryLevel.inject(85)

        device.$id.inject(UUID())
        device.$name.inject(name)
        device.$state.inject(state)
        device.$nearby.inject(nearby)

        device.bloodPressure.$features.inject([
            .bodyMovementDetectionSupported,
            .irregularPulseDetectionSupported
        ])
        device.bloodPressure.$bloodPressureMeasurement.inject(bloodPressureMeasurement)

        device.weightScale.$features.inject(WeightScaleFeature(
            weightResolution: weightResolution,
            heightResolution: heightResolution,
            options: .timeStampSupported
        ))
        device.weightScale.$weightMeasurement.inject(weightMeasurement)

        device.$connect.inject { @MainActor [weak device] in
            guard let device else {
                return
            }
            device.$state.inject(.connecting)

            try? await Task.sleep(for: .seconds(1))

            if case .connecting = device.state {
                device.$state.inject(.connected)
            }
        }

        device.$disconnect.inject { @MainActor [weak device] in
            device?.$state.inject(.disconnected)
        }

        device.$state.enableSubscriptions()
        device.$advertisementData.enableSubscriptions()
        device.$nearby.enableSubscriptions()

        device.battery.$batteryLevel.enableSubscriptions()
        device.battery.$batteryLevel.enablePeripheralSimulation()

        device.bloodPressure.$bloodPressureMeasurement.enableSubscriptions()
        device.bloodPressure.$bloodPressureMeasurement.enablePeripheralSimulation()

        device.weightScale.$weightMeasurement.enableSubscriptions()
        device.weightScale.$weightMeasurement.enablePeripheralSimulation()

        return device
    }
}


extension BloodPressureMeasurement {
    /// Create a mock blood pressure measurement.
    /// - Parameters:
    ///   - systolic: The systolic value.
    ///   - diastolic: The diastolic value.
    ///   - meanArterialPressure: The mean arterial perssure.
    ///   - unit: The unit.
    ///   - timeStamp: The timestamp.
    ///   - pulseRate: The pulse rate.
    ///   - userId: The associated user id.
    ///   - status: The measurement status.
    /// - Returns:
    @_spi(TestingSupport)
    public static func mock(
        systolic: MedFloat16 = 103,
        diastolic: MedFloat16 = 64,
        meanArterialPressure: MedFloat16 = 77,
        unit: BloodPressureMeasurement.Unit = .mmHg,
        timeStamp: DateTime? = DateTime(year: 2024, month: .june, day: 5, hours: 12, minutes: 33, seconds: 11),
        pulseRate: MedFloat16 = 62,
        userId: UInt8 = 1,
        status: BloodPressureMeasurement.Status = []
    ) -> BloodPressureMeasurement {
        BloodPressureMeasurement(
            systolic: systolic,
            diastolic: diastolic,
            meanArterialPressure: meanArterialPressure,
            unit: unit,
            timeStamp: timeStamp,
            pulseRate: pulseRate,
            userId: userId,
            measurementStatus: status
        )
    }
}


extension WeightMeasurement {
    /// Create a mock weight measurement.
    /// - Parameters:
    ///   - weight: The weight value.
    ///   - unit: The unit.
    ///   - timeStamp: The timestamp.
    ///   - userId: The associated user id.
    ///   - additionalInfo: Additional measurement information like BMI and height.
    /// - Returns:
    @_spi(TestingSupport)
    public static func mock(
        weight: UInt16 = 8400,
        unit: WeightMeasurement.Unit = .si,
        timeStamp: DateTime? = DateTime(year: 2024, month: .june, day: 5, hours: 12, minutes: 33, seconds: 11),
        userId: UInt8? = 1,
        additionalInfo: AdditionalInfo? = .init(bmi: 230, height: 1790)
    ) -> WeightMeasurement {
        WeightMeasurement(
            weight: weight,
            unit: unit,
            timeStamp: timeStamp,
            userId: userId,
            additionalInfo: additionalInfo
        )
    }
}
