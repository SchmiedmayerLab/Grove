//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


@available(iOS 17, macOS 14, macCatalyst 17, tvOS 17, watchOS 10, visionOS 1, *)
@SpeziBluetooth
protocol BaseVisitor {
    mutating func visit<Action: _BluetoothPeripheralAction>(_ action: DeviceAction<Action>)

    mutating func visit<Value>(_ state: DeviceState<Value>)
}


@available(iOS 17, macOS 14, macCatalyst 17, tvOS 17, watchOS 10, visionOS 1, *)
extension BaseVisitor {
    func visit<Action: _BluetoothPeripheralAction>(_ action: DeviceAction<Action>) {}

    func visit<Value>(_ state: DeviceState<Value>) {}
}
