//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


@available(iOS 17, macOS 14, macCatalyst 17, tvOS 17, watchOS 10, visionOS 1, *)
protocol DeviceVisitable {
    @SpeziBluetooth
    func accept<Visitor: DeviceVisitor>(_ visitor: inout Visitor)
}


@SpeziBluetooth
@available(iOS 17, macOS 14, macCatalyst 17, tvOS 17, watchOS 10, visionOS 1, *)
protocol DeviceVisitor: BaseVisitor {
    mutating func visit<S: BluetoothService>(_ service: Service<S>)
}


@available(iOS 17, macOS 14, macCatalyst 17, tvOS 17, watchOS 10, visionOS 1, *)
extension BluetoothDevice {
    @SpeziBluetooth
    func accept<Visitor: DeviceVisitor>(_ visitor: inout Visitor) {
        let mirror = Mirror(reflecting: self)
        for (_, child) in mirror.children {
            if let visitable = child as? DeviceVisitable {
                visitable.accept(&visitor)
            } else if child is ServiceVisitable {
                preconditionFailure("@Characteristic declaration found in \(Self.self). @Characteristic cannot be used within the BluetoothDevice class!")
            }
        }
    }
}
