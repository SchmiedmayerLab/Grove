//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


@available(iOS 17, macOS 14, macCatalyst 17, tvOS 17, watchOS 10, visionOS 1, *)
protocol ServiceVisitable {
    @SpeziBluetooth
    func accept<Visitor: ServiceVisitor>(_ visitor: inout Visitor)
}


@available(iOS 17, macOS 14, macCatalyst 17, tvOS 17, watchOS 10, visionOS 1, *)
@SpeziBluetooth
protocol ServiceVisitor: BaseVisitor {
    mutating func visit<Value>(_ characteristic: Characteristic<Value>)
}


@available(iOS 17, macOS 14, macCatalyst 17, tvOS 17, watchOS 10, visionOS 1, *)
extension BluetoothService {
    @SpeziBluetooth
    func accept<Visitor: ServiceVisitor>(_ visitor: inout Visitor) {
        let mirror = Mirror(reflecting: self)
        for (_, child) in mirror.children {
            if let visitable = child as? ServiceVisitable {
                visitable.accept(&visitor)
            } else if child is DeviceVisitable {
                preconditionFailure("@Service declaration found in \(Self.self). @Service cannot be used within BluetoothService classes!")
            }
        }
    }
}
