//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


@available(iOS 18, macOS 15, watchOS 11, *)
protocol DeviceVisitable {
    @GroveBluetooth
    func accept<Visitor: DeviceVisitor>(_ visitor: inout Visitor)
}


@available(iOS 18, macOS 15, watchOS 11, *)
@GroveBluetooth
protocol DeviceVisitor: BaseVisitor {
    mutating func visit<S: BluetoothService>(_ service: Service<S>)
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension BluetoothDevice {
    @GroveBluetooth
    func accept<Visitor: DeviceVisitor>(_ visitor: inout Visitor) {
        let mirror = Mirror(reflecting: self)
        for (_, child) in mirror.children {
            if let visitable = child as? any DeviceVisitable {
                visitable.accept(&visitor)
            } else if child is any ServiceVisitable {
                preconditionFailure("@Characteristic declaration found in \(Self.self). @Characteristic cannot be used within the BluetoothDevice class!")
            }
        }
    }
}
