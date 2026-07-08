//
// This source file is part of the Stanford SpeziDevices open source project
//
// SPDX-FileCopyrightText: 2024 Stanford University
//
// SPDX-License-Identifier: MIT
//

@_spi(TestingSupport)
import SpeziBluetooth
import SpeziBluetoothServices
@_spi(TestingSupport)
@testable import SpeziDevices
import SpeziFoundation
import SpeziTesting
import Testing

@MainActor
@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
@Suite
struct PairedDevicesTests {
    @Test
    func pairDevice() async throws {
        let device = MockDevice.createMockDevice()
        let devices = PairedDevices()


        // ensure PairedDevices gets injected into the MockDevice
        withDependencyResolution {
            device
            devices
        }

        async let _ = devices.run() // make sure lifecycle runs

        device.isInPairingMode = true


        #expect(!devices.isConnected(device: device.id))
        #expect(!devices.isPaired(device))

        devices.configure(device: device, accessing: device.$state, device.$advertisementData, device.$nearby)

        try await Task.sleep(for: .milliseconds(50))

        try await devices.pair(with: device)


        #expect(devices.isPaired(device))
        #expect(devices.isConnected(device: device.id))

        #expect(devices.pairedDevices?.count == 1)
        let deviceInfo = try #require(devices.pairedDevices?.first)

        #expect(deviceInfo.id == device.id)
        #expect(deviceInfo.deviceType == MockDevice.deviceTypeIdentifier)
        #expect(deviceInfo.icon == .system("sensor"))
        #expect(deviceInfo.model == device.deviceInformation.modelNumber)
        #expect(deviceInfo.name == "My Mock Device") // ensure this uses the appearance name
        #expect(deviceInfo.lastBatteryPercentage == 85)

        let initialLastSeen = deviceInfo.lastSeen

        device.battery.$batteryLevel.inject(71)
        await device.disconnect()
        device.$nearby.inject(false)

        #expect(device.state == .disconnected)

        try await Task.sleep(for: .milliseconds(50))


        #expect(deviceInfo.lastSeen > initialLastSeen) // should be later and updated on disconnect
        #expect(deviceInfo.lastBatteryPercentage == 71) // should have captured the updated battery


        devices.updateName(for: deviceInfo, name: "Custom Name")
        #expect(deviceInfo.name == "Custom Name")

        let recentLastSeen = deviceInfo.lastSeen

        // test storage persistence!
        try devices.refreshPairedDevices()
        try {
            #expect(devices.pairedDevices?.count == 1)
            let info0 = try #require(devices.pairedDevices?.first)
            #expect(info0.name == "Custom Name")
            #expect(info0.lastBatteryPercentage == 71)
            #expect(info0.lastSeen == recentLastSeen)
        }()


        try await device.connect()
        try await Task.sleep(for: .seconds(1.1))
        #expect(device.state == .connected)


        try await devices.forgetDevice(id: device.id)
        try await Task.sleep(for: .milliseconds(500))
        
        #expect(device.state == .disconnected)
        #expect(devices.pairedDevices?.isEmpty == true)
        #expect(devices.discoveredDevices.isEmpty)
    }

    @Test
    func pairingErrors() async throws {
        let device = MockDevice.createMockDevice()
        let devices = PairedDevices()

        withDependencyResolution {
            devices
        }

        device.isInPairingMode = true
        devices.configure(device: device, accessing: device.$state, device.$advertisementData, device.$nearby)

        device.$nearby.inject(false)
        let error = await #expect(throws: DevicePairingError.self) { try await devices.pair(with: device) }
        #expect(error == .invalidState)
        device.$nearby.inject(true)

        try await device.connect()
        let error1 = await #expect(throws: DevicePairingError.self) { try await devices.pair(with: device) }
        #expect(error1 == .invalidState)
        await device.disconnect()

        device.isInPairingMode = false
        let error2 = await #expect(throws: DevicePairingError.self) { try await devices.pair(with: device) }
        #expect(error2 == .notInPairingMode)
        device.isInPairingMode = true
        device.$advertisementData.inject(.init())

        try await Task.sleep(for: .milliseconds(200))

        try await #require(throws: TimeoutError.self) { try await devices.pair(with: device, timeout: .milliseconds(200)) }
    }
    
    @Test
    func pairingCancellation() async throws {
        let device = MockDevice.createMockDevice()
        let devices = PairedDevices()

        withDependencyResolution {
            devices
        }

        device.isInPairingMode = true
        devices.configure(device: device, accessing: device.$state, device.$advertisementData, device.$nearby)

        try await Task.sleep(for: .milliseconds(50))

        let task = Task {
            try await devices.pair(with: device)
        }

        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        
        await #expect(throws: CancellationError.self) { try await task.value }

        #expect(device.state == .disconnected)
    }

    @Test
    func failedPairing() async throws {
        let device = MockDevice.createMockDevice()
        let devices = PairedDevices()

        withDependencyResolution {
            device
            devices
        }

        device.isInPairingMode = true

        devices.configure(device: device, accessing: device.$state, device.$advertisementData, device.$nearby)

        try await Task.sleep(for: .milliseconds(50))

        let task = Task {
            try await devices.pair(with: device)
        }

        try await Task.sleep(for: .milliseconds(1150))
        await device.disconnect()

        let error = await #expect(throws: DevicePairingError.self) { try await task.value }
        #expect(error == .deviceDisconnected)

        #expect(device.state == .disconnected)
    }
}
