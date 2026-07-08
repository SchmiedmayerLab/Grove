//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Disconnect from the Bluetooth peripheral.
///
/// For more information refer to ``DeviceActions/disconnect``
@available(iOS 17, macOS 14, macCatalyst 17, tvOS 17, watchOS 10, visionOS 1, *)
public struct BluetoothDisconnectAction: _BluetoothPeripheralAction, Sendable {
    public typealias ClosureType = @Sendable () async -> Void

    private let content: _PeripheralActionContent<ClosureType>

    @_documentation(visibility: internal)
    public init(_ content: _PeripheralActionContent<ClosureType>) {
        self.content = content
    }

    public func callAsFunction() async {
        switch content {
        case let .peripheral(peripheral):
            await peripheral.disconnect()
        case let .injected(closure):
            await closure()
        }
    }
}
