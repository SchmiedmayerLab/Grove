//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CoreBluetooth


@available(iOS 18, macOS 15, watchOS 11, *)
extension CBCharacteristicProperties {
    var supportsNotifications: Bool {
        contains(.notify) || contains(.notifyEncryptionRequired)
            || contains(.indicate) || contains(.indicateEncryptionRequired) // indicate is notify whith an ACK
    }
}
