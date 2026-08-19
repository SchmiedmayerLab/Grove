//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
final class BluetoothWorkItem {
    private let workItem: DispatchWorkItem

    init(handler: @GroveBluetooth @escaping @Sendable () -> Void) {
        self.workItem = DispatchWorkItem {
            GroveBluetooth.assumeIsolated {
                handler()
            }
        }
    }

    func schedule(for deadline: DispatchTime, in queue: DispatchSerialQueue? = nil) {
        let queue = queue ?? GroveBluetooth.shared.dispatchQueue
        queue.asyncAfter(deadline: deadline, execute: workItem)
    }

    func cancel() {
        workItem.cancel()
    }

    deinit {
        workItem.cancel()
    }
}
