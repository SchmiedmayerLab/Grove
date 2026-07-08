//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


@available(iOS 17, macOS 14, macCatalyst 17, tvOS 17, watchOS 10, visionOS 1, *)
final class BluetoothWorkItem {
    private let workItem: DispatchWorkItem

    init(handler: @SpeziBluetooth @escaping @Sendable () -> Void) {
        self.workItem = DispatchWorkItem {
            SpeziBluetooth.assumeIsolatedIfAvailableOrTask {
                handler()
            }
        }
    }

    func schedule(for deadline: DispatchTime) {
        SpeziBluetooth.shared.dispatchQueue.asyncAfter(deadline: deadline, execute: workItem)
    }

    func cancel() {
        workItem.cancel()
    }

    deinit {
        workItem.cancel()
    }
}
