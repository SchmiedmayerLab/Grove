//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


@SpeziBluetooth
@available(iOS 17, macOS 14, macCatalyst 17, tvOS 17, watchOS 10, visionOS 1, *)
class ServicePeripheralInjection<S: BluetoothService>: Sendable {
    private let bluetooth: Bluetooth
    let peripheral: BluetoothPeripheral
    private let serviceId: BTUUID
    private let state: Service<S>.State

    private weak var service: GATTService? {
        didSet {
            state.serviceState = .init(from: service)
        }
    }


    init(bluetooth: Bluetooth, peripheral: BluetoothPeripheral, serviceId: BTUUID, service: GATTService?, state: Service<S>.State) {
        self.bluetooth = bluetooth
        self.peripheral = peripheral
        self.serviceId = serviceId
        self.state = state
        self.service = service
    }

    func setup() {
        trackServicesUpdate()
    }

    private func trackServicesUpdate() {
        peripheral.onChange(of: \.services) { [weak self] services in
            guard let self = self,
                  let service = services?[self.serviceId] else {
                return
            }

            self.trackServicesUpdate()
            self.service = service
        }
    }

    deinit {
        bluetooth.notifyDeviceDeinit(for: peripheral.id)
    }
}
