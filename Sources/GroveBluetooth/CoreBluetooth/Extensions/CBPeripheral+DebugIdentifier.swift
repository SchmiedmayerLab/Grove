//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CoreBluetooth


// CustomDebugStringConvertible is already implemented for NSObjects. So we just define a custom property
@available(iOS 18, macOS 15, watchOS 11, *)
extension CBPeripheral {
    var debugIdentifier: String {
        if let name {
            "'\(name)' @ \(identifier)"
        } else {
            "\(identifier)"
        }
    }
}
