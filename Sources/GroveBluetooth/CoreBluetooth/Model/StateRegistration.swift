//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// An state change handler registration for the Bluetooth state.
///
/// It automatically cancels the subscription once this value is de-initialized.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct StateRegistration: ~Copyable {
    private let id: UUID
    private weak var storage: BluetoothManagerStorage?

    init(id: UUID, storage: BluetoothManagerStorage? = nil) {
        self.id = id
        self.storage = storage
    }

    private static func cancel(id: UUID, storage: BluetoothManagerStorage?) {
        guard let storage else {
            return
        }

        let id = id
        Task.detached { @GroveBluetooth in
            storage.unsubscribe(for: id)
        }
    }
    
    /// Cancels the subscription.
    public func cancel() {
        Self.cancel(id: id, storage: storage)
    }

    deinit {
        Self.cancel(id: id, storage: storage)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension StateRegistration: Sendable {}
