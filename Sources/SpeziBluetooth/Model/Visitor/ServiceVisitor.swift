//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


@available(iOS 18, macOS 15, watchOS 11, *)
protocol ServiceVisitable {
    @SpeziBluetooth
    func accept<Visitor: ServiceVisitor>(_ visitor: inout Visitor)
}


@available(iOS 18, macOS 15, watchOS 11, *)
@SpeziBluetooth
protocol ServiceVisitor: BaseVisitor {
    mutating func visit<Value>(_ characteristic: Characteristic<Value>)
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension BluetoothService {
    @SpeziBluetooth
    func accept<Visitor: ServiceVisitor>(_ visitor: inout Visitor) {
        let mirror = Mirror(reflecting: self)
        for (_, child) in mirror.children {
            if let visitable = child as? any ServiceVisitable {
                visitable.accept(&visitor)
            } else if child is any DeviceVisitable {
                preconditionFailure("@Service declaration found in \(Self.self). @Service cannot be used within BluetoothService classes!")
            }
        }
    }
}
