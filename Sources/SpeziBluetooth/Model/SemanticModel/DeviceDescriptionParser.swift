//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


@available(iOS 17, macOS 14, macCatalyst 17, tvOS 17, watchOS 10, visionOS 1, *)
private struct CharacteristicsBuilder: ServiceVisitor {
    var characteristics: Set<CharacteristicDescription> = []

    mutating func visit<Value>(_ characteristic: Characteristic<Value>) {
        characteristics.insert(characteristic.description)
    }
}


@available(iOS 17, macOS 14, macCatalyst 17, tvOS 17, watchOS 10, visionOS 1, *)
private struct ServiceDescriptionBuilder: DeviceVisitor {
    var configurations: Set<ServiceDescription> = []

    mutating func visit<S: BluetoothService>(_ service: Service<S>) {
        var visitor = CharacteristicsBuilder()
        service.wrappedValue.accept(&visitor)

        let configuration = ServiceDescription(serviceId: service.id, characteristics: visitor.characteristics)
        configurations.insert(configuration)
    }
}


@available(iOS 17, macOS 14, macCatalyst 17, tvOS 17, watchOS 10, visionOS 1, *)
extension BluetoothDevice {
    @SpeziBluetooth
    static func parseDeviceDescription() -> DeviceDescription {
        let device = Self()

        var builder = ServiceDescriptionBuilder()
        device.accept(&builder)
        return DeviceDescription(services: builder.configurations)
    }
}


@available(iOS 17, macOS 14, macCatalyst 17, tvOS 17, watchOS 10, visionOS 1, *)
extension DeviceDiscoveryDescriptor {
    @SpeziBluetooth
    func parseDiscoveryDescription() -> DiscoveryDescription {
        let deviceDescription = deviceType.parseDeviceDescription()
        return DiscoveryDescription(discoverBy: discoveryCriteria, device: deviceDescription)
    }
}


@available(iOS 17, macOS 14, macCatalyst 17, tvOS 17, watchOS 10, visionOS 1, *)
extension Set where Element == DeviceDiscoveryDescriptor {
    var deviceTypes: [any BluetoothDevice.Type] {
        map { configuration in
            configuration.deviceType
        }
    }

    @SpeziBluetooth
    func parseDiscoveryDescription() -> Set<DiscoveryDescription> {
        Set<DiscoveryDescription>(map { $0.parseDiscoveryDescription() })
    }
}
