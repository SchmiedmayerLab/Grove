//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


@available(iOS 18, macOS 15, watchOS 11, *)
@SpeziBluetooth
protocol BaseVisitor {
    mutating func visit<Action: _BluetoothPeripheralAction>(_ action: DeviceAction<Action>)

    mutating func visit<Value>(_ state: DeviceState<Value>)
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension BaseVisitor {
    func visit<Action: _BluetoothPeripheralAction>(_ action: DeviceAction<Action>) {}

    func visit<Value>(_ state: DeviceState<Value>) {}
}
