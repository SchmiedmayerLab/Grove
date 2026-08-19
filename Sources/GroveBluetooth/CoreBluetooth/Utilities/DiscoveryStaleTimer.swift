//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
final class DiscoveryStaleTimer {
    let targetDevice: UUID
    /// The dispatch work item that schedules the next stale timer.
    private let workItem: BluetoothWorkItem

    init(device: UUID, handler: @GroveBluetooth @escaping @Sendable () -> Void) {
        // make sure that you don't create a reference cycle through the closure above!

        self.targetDevice = device
        self.workItem = BluetoothWorkItem(handler: handler)
    }


    func cancel() {
        workItem.cancel()
    }

    func schedule(for timeout: TimeInterval, in queue: DispatchSerialQueue) {
        // `DispatchTime` only allows for integer time
        let milliSeconds = Int(timeout * 1000)
        workItem.schedule(for: .now() + .milliseconds(milliSeconds), in: queue)
    }

    deinit {
        cancel()
    }
}
