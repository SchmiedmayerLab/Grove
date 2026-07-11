//
// This source file is part of the Stanford SpeziDevices open source project
//
// SPDX-FileCopyrightText: 2024 Stanford University
//
// SPDX-License-Identifier: MIT
//

import CoreBluetooth
import Foundation
import OSLog
@_spi(TestingSupport)
import SpeziBluetooth
import SpeziBluetoothServices
@_spi(Migration)
import SpeziDevices
import SpeziNumerics


/// Implementation of a Omron Blood Pressure Cuff.
///
/// This device class currently supports the following models:
/// * `BP5250`
/// * `BP7000`
/// * `EVOLV`
///
/// - Note: It is likely that other Omron Blood Pressure Cuffs are also supported with this implementation. However, they will be displayed with a generic device icon
///   in `SpeziDevicesUI` related components.
@available(iOS 18, macOS 15, watchOS 11, *)
public final class OmronBloodPressureCuff: BluetoothDevice, Identifiable, OmronHealthDevice, BatteryPoweredDevice, @unchecked Sendable {
    public static let appearance: DeviceAppearance = .variants(defaultAppearance: Appearance(name: "Omron Blood Pressure Cuff"), variants: [
        Variant(
            id: "omron-bp5250",
            name: "BP5250",
            icon: .asset("Omron-BP5250", bundle: .module),
            criteria: .nameSubstring("BLEsmart_00000160"),
            .manufacturer(.omronHealthcareCoLtd)
        ),
        Variant(id: "omron-evolv", name: "EVOLV", icon: .asset("Omron-EVOLV", bundle: .module), criteria: .nameSubstring("BLEsmart_0000021F")),
        Variant(id: "omron-bp7000", name: "BP7000", icon: .asset("Omron-BP7000", bundle: .module), criteria: .nameSubstring("BLEsmart_0000011F"))
    ])

    private let logger = Logger(subsystem: "ENGAGEHF", category: "BloodPressureCuffDevice")

    @DeviceState(\.id)
    public var id: UUID
    @DeviceState(\.name)
    public var name: String?
    @DeviceState(\.state)
    public var state: PeripheralState
    @DeviceState(\.advertisementData)
    public var advertisementData: AdvertisementData
    @DeviceState(\.nearby)
    public var nearby

    @Service public var deviceInformation = DeviceInformationService()

    @Service public var time = CurrentTimeService()
    @Service public var battery = BatteryService()
    @Service public var bloodPressure = BloodPressureService()

    @DeviceAction(\.connect)
    public var connect
    @DeviceAction(\.disconnect)
    public var disconnect

    @Dependency(HealthMeasurements.self)
    private var measurements: HealthMeasurements?
    @Dependency(PairedDevices.self)
    private var pairedDevices: PairedDevices?

    @SpeziBluetooth private var didReceiveFirstTimeNotification = false

    /// Initialize the device.
    public required init() {}

    public func configure() {
        $state.onChange { [weak self] value in
            await self?.handleStateChange(value)
        }

        battery.$batteryLevel.onChange { [weak self] value in
            await self?.handleBatteryChange(value)
        }
        time.$currentTime.onChange { [weak self] value in
            await self?.handleCurrentTimeChange(value)
        }

        if let pairedDevices {
            pairedDevices.configure(device: self, accessing: $state, $advertisementData, $nearby)
        }
        if let measurements {
            measurements.configureReceivingMeasurements(for: self, on: \.bloodPressure)
        }
    }

    @SpeziBluetooth
    private func handleStateChange(_ state: PeripheralState) {
        logger.debug("\(Self.self) \(self.label), \(self.id) changed state to \(state).")
        switch state {
        case .connecting, .connected:
            break
        case .disconnected, .disconnecting:
            didReceiveFirstTimeNotification = false
        }
    }

    @MainActor
    private func handleBatteryChange(_ level: UInt8) {
        pairedDevices?.signalDevicePaired(self)
    }

    @SpeziBluetooth
    private func handleCurrentTimeChange(_ time: CurrentTime) async {
        logger.debug("Received updated device time for \(self.label) is \(String(describing: time))")

        // We always update time on the first current time notification. That's how it is expected for Omron devices.
        // First time notification might come before we are considered fully connected (from SpeziBluetooth point of view).
        // However, this will trigger another notification anyways, which will then arrive once we are connected
        // and the iOS Bluetooth Pairing dialog was dismissed.
        if !didReceiveFirstTimeNotification {
            didReceiveFirstTimeNotification = true
            do {
                try await self.time.synchronizeDeviceTime(threshold: .zero)
            } catch {
                logger.warning("Failed to update current time: \(error)")
            }
        }

        if case .connected = state {
            // for Omron we take that as a signal that device is paired
            await pairedDevices?.signalDevicePaired(self)
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
@_spi(TestingSupport)
extension OmronBloodPressureCuff {
    /// Create a mock instance.
    /// - Parameters:
    ///   - systolic: The mock systolic value.
    ///   - diastolic: The mock diastolic value.
    ///   - pulseRate: The mock pulse rate value.
    ///   - state: The initial state.
    ///   - nearby: The nearby state.
    ///   - manufacturerData: The initial manufacturer data.
    ///   - timeStamp: The timestamp of the latest measurement.
    ///   - simulateRealDevice: If `true`, the real onChange handlers with be set up with the mock device.
    /// - Returns: Returns the mock device instance.
    public static func createMockDevice( // swiftlint:disable:this function_body_length
        systolic: MedFloat16 = 103,
        diastolic: MedFloat16 = 64,
        pulseRate: MedFloat16 = 62,
        name: String = "BLEsmart_00000160",
        state: PeripheralState = .disconnected,
        nearby: Bool = true,
        manufacturerData: OmronManufacturerData = OmronManufacturerData(pairingMode: .pairingMode, users: [
            .init(id: 1, sequenceNumber: 2, recordsNumber: 1)
        ]),
        timeStamp: DateTime = DateTime(year: 2024, month: .june, day: 5, hours: 12, minutes: 33, seconds: 11),
        simulateRealDevice: Bool = false
    ) -> OmronBloodPressureCuff {
        let device = OmronBloodPressureCuff()

        device.$id.inject(UUID())
        device.$name.inject(name)
        device.$state.inject(state)
        device.$nearby.inject(nearby)

        device.deviceInformation.$manufacturerName.inject("Mock Blood Pressure Cuff")
        device.deviceInformation.$modelNumber.inject(OmronModel.bp5250.rawValue)
        device.deviceInformation.$hardwareRevision.inject("2")
        device.deviceInformation.$firmwareRevision.inject("1.0")

        device.battery.$batteryLevel.inject(85)

        let features: BloodPressureFeature = [
            .bodyMovementDetectionSupported,
            .irregularPulseDetectionSupported
        ]

        let measurement = BloodPressureMeasurement(
            systolic: systolic,
            diastolic: diastolic,
            meanArterialPressure: 77,
            unit: .mmHg,
            timeStamp: timeStamp,
            pulseRate: pulseRate,
            userId: 1,
            measurementStatus: []
        )

        device.bloodPressure.$features.inject(features)
        device.bloodPressure.$bloodPressureMeasurement.inject(measurement)

        let advertisementData = AdvertisementData(manufacturerData: manufacturerData.encode())
        device.$advertisementData.inject(advertisementData)

        device.$connect.inject { @MainActor [weak device] in
            guard let device else {
                return
            }

            device.$state.inject(.connecting)

            try? await Task.sleep(for: .seconds(2))

            if case .connecting = device.state {
                device.$state.inject(.connected)

                if case .pairingMode = device.manufacturerData?.pairingMode {
                    try? await Task.sleep(for: .seconds(1))
                    device.battery.$batteryLevel.inject(100)
                }
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

        device.time.$currentTime.enableSubscriptions()
        device.time.$currentTime.enablePeripheralSimulation()

        device.bloodPressure.$bloodPressureMeasurement.enableSubscriptions()
        device.bloodPressure.$bloodPressureMeasurement.enablePeripheralSimulation()

        if simulateRealDevice {
            device.$state.onChange { [weak device] state in
                await device?.handleStateChange(state)
            }

            device.time.$currentTime.onChange { [weak device] value in
                await device?.handleCurrentTimeChange(value)
            }
            device.battery.$batteryLevel.onChange { [weak device] value in
                await device?.handleBatteryChange(value)
            }
        }

        return device
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
@_spi(Migration)
extension OmronBloodPressureCuff: DeviceVariantMigration {
    public static func selectAppearance(for deviceInfo: PairedDeviceInfo) -> (appearance: Appearance, variantId: String?) {
        appearance.appearance { variant in
            variant.name == deviceInfo.model
        }
    }
}
