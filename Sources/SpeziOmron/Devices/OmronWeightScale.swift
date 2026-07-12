//
// This source file is part of the ENGAGE-HF project based on the Stanford Spezi Template Application project
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
import SpeziFoundation


/// Implementation of Omron SC150 Weight Scale.
@available(iOS 18, macOS 15, watchOS 11, *)
public final class OmronWeightScale: BluetoothDevice, Identifiable, OmronHealthDevice, @unchecked Sendable {
    public static let appearance: DeviceAppearance = .variants(defaultAppearance: Appearance(name: "Omron Weight Scale"), variants: [
        Variant(
            id: "omron-sc150",
            name: "SC-150",
            icon: .asset("Omron-SC-150", bundle: .module),
            criteria: .nameSubstring("BLESmart_00010112"),
            .manufacturer(.omronHealthcareCoLtd, manufacturerData: pairingModeDescriptor)
        )
    ])

    private static var pairingModeDescriptor: DataDescriptor {
        DataDescriptor(data: OmronManufacturerDataPrefix(.pairingMode).encode(), mask: OmronManufacturerDataPrefix(bitMaskFor: .pairingMode).encode())
    }

    private let logger = Logger(subsystem: "ENGAGEHF", category: "WeightScale")

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
    @Service public var weightScale = WeightScaleService()

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

        time.$currentTime.onChange { [weak self] value in
            await self?.handleCurrentTimeChange(value)
        }

        if let pairedDevices {
            pairedDevices.configure(device: self, accessing: $state, $advertisementData, $nearby)
        }
        if let measurements {
            measurements.configureReceivingMeasurements(for: self, on: \.weightScale)
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

    @SpeziBluetooth
    private func handleCurrentTimeChange(_ time: CurrentTime) async {
        logger.debug("Received updated device time for \(self.label): \(String(describing: time))")

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
extension OmronWeightScale {
    /// Create a mock instance.
    /// - Parameters:
    ///   - weight: The weight value.
    ///   - resolution: The weight resolution.
    ///   - state: The initial state.
    ///   - nearby: The nearby state.
    ///   - manufacturerData: The initial manufacturer data.
    ///   - timeStamp: The timestamp of the latest measurement.
    ///   - simulateRealDevice: If `true`, the real onChange handlers with be set up with the mock device.
    /// - Returns: Returns the mock device instance.
    public static func createMockDevice( // swiftlint:disable:this function_body_length
        weight: UInt16 = 8400,
        resolution: WeightScaleFeature.WeightResolution = .resolution5g,
        state: PeripheralState = .disconnected,
        nearby: Bool = true,
        manufacturerData: OmronManufacturerData = OmronManufacturerData(pairingMode: .pairingMode, users: [
            .init(id: 1, sequenceNumber: 2, recordsNumber: 1)
        ]),
        timeStamp: DateTime = DateTime(year: 2024, month: .june, day: 5, hours: 12, minutes: 33, seconds: 11),
        simulateRealDevice: Bool = false
    ) -> OmronWeightScale {
        let device = OmronWeightScale()

        device.$id.inject(UUID())
        device.$name.inject("BLESmart_00010112")
        device.$state.inject(state)
        device.$nearby.inject(nearby)

        device.deviceInformation.$manufacturerName.inject("Mock Weight Scale")
        device.deviceInformation.$modelNumber.inject(OmronModel.sc150.rawValue)
        device.deviceInformation.$hardwareRevision.inject("2")
        device.deviceInformation.$firmwareRevision.inject("1.0")

        // mocks the values as reported by the real device
        let features = WeightScaleFeature(
            weightResolution: resolution,
            heightResolution: .unspecified,
            options: .timeStampSupported
        )

        let measurement = WeightMeasurement(
            weight: weight,
            unit: .si,
            timeStamp: timeStamp
        )

        device.weightScale.$features.inject(features)
        device.weightScale.$weightMeasurement.inject(measurement)

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
                    device.time.$currentTime.inject(CurrentTime(time: .init(from: .now)))
                }
            }
        }

        device.$disconnect.inject { @MainActor [weak device] in
            device?.$state.inject(.disconnected)
        }

        device.$state.enableSubscriptions()
        device.$advertisementData.enableSubscriptions()
        device.$nearby.enableSubscriptions()

        device.time.$currentTime.enableSubscriptions()
        device.time.$currentTime.enablePeripheralSimulation()

        device.weightScale.$weightMeasurement.enableSubscriptions()
        device.weightScale.$weightMeasurement.enablePeripheralSimulation()

        if simulateRealDevice {
            device.$state.onChange { [weak device] state in
                await device?.handleStateChange(state)
            }

            device.time.$currentTime.onChange { [weak device] value in
                await device?.handleCurrentTimeChange(value)
            }
        }

        return device
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
@_spi(Migration)
extension OmronWeightScale: DeviceVariantMigration {
    public static func selectAppearance(for deviceInfo: PairedDeviceInfo) -> (appearance: Appearance, variantId: String?) {
        appearance.appearance { variant in
            variant.name == deviceInfo.model
        }
    }
}
