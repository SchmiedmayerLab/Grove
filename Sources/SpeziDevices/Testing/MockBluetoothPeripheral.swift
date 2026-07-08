//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziBluetooth


/// Mock peripheral used for internal previews.
@_spi(TestingSupport)
@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
public struct MockBluetoothPeripheral: GenericBluetoothPeripheral {
    public let label: String
    public let state: PeripheralState
    public let requiresUserAttention: Bool


    public init(label: String, state: PeripheralState, requiresUserAttention: Bool = false) {
        self.label = label
        self.state = state
        self.requiresUserAttention = requiresUserAttention
    }
}
