//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Read the current RSSI from the Bluetooth peripheral.
///
/// For more information refer to ``DeviceActions/readRSSI``
@available(iOS 18, macOS 15, watchOS 11, *)
public struct ReadRSSIAction: _BluetoothPeripheralAction, Sendable {
    public typealias ClosureType = @Sendable () async throws -> Int

    private let content: _PeripheralActionContent<ClosureType>

    @_documentation(visibility: internal)
    public init(_ content: _PeripheralActionContent<ClosureType>) {
        self.content = content
    }


    @discardableResult
    public func callAsFunction() async throws -> Int {
        switch content {
        case let .peripheral(peripheral):
            try await peripheral.readRSSI()
        case let .injected(closure):
            try await closure()
        }
    }
}
