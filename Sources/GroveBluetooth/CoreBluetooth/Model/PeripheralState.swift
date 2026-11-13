//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Atomics
public import CoreBluetooth


/// Describes the state of a Bluetooth peripheral.
@available(iOS 18, macOS 15, watchOS 11, *)
public enum PeripheralState: UInt8 {
    /// The peripheral is disconnected.
    case disconnected
    /// The peripheral is currently establishing a connection.
    case connecting
    /// The peripheral is connected.
    case connected
    /// The peripheral is currently disconnecting.
    case disconnecting
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension PeripheralState: RawRepresentable, AtomicValue {}


@available(iOS 18, macOS 15, watchOS 11, *)
extension PeripheralState: Hashable, Sendable {}


@available(iOS 18, macOS 15, watchOS 11, *)
extension PeripheralState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .disconnected:
            "disconnected"
        case .connecting:
            "connecting"
        case .connected:
            "connected"
        case .disconnecting:
            "disconnecting"
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension PeripheralState {
    /// Derive peripheral state from CoreBluetooth
    public init(from state: CBPeripheralState) {
        switch state {
        case .disconnected:
            self = .disconnected
        case .connecting:
            self = .connecting
        case .connected:
            self = .connected
        case .disconnecting:
            self = .disconnecting
        @unknown default:
            self = .disconnected
        }
    }
}
