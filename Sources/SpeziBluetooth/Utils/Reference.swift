//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@available(iOS 17, macOS 14, macCatalyst 17, tvOS 17, watchOS 10, visionOS 1, *)
protocol AnyWeakDeviceReference {
    var anyValue: (any BluetoothDevice)? { get }

    var typeName: String { get }
}


@available(iOS 17, macOS 14, macCatalyst 17, tvOS 17, watchOS 10, visionOS 1, *)
struct WeakReference<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value? = nil) {
        self.value = value
    }
}


@available(iOS 17, macOS 14, macCatalyst 17, tvOS 17, watchOS 10, visionOS 1, *)
extension WeakReference: AnyWeakDeviceReference where Value: BluetoothDevice {
    var anyValue: (any BluetoothDevice)? {
        value
    }

    var typeName: String {
        "\(Value.self)"
    }
}
