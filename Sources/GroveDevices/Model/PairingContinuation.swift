//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFoundation


/// Stores pairing state information.
@available(iOS 18, macOS 15, watchOS 11, *)
struct PairingContinuation {
    private let pairingContinuation: CheckedContinuation<Void, any Error>

    /// Create a new pairing continuation management object.
    init(_ continuation: CheckedContinuation<Void, any Error>) {
        self.pairingContinuation = continuation
    }

    func signalTimeout() {
        pairingContinuation.resume(with: .failure(TimeoutError()))
    }

    func signalCancellation() {
        pairingContinuation.resume(with: .failure(CancellationError()))
    }

    /// Signal that the device was successfully paired.
    ///
    /// This method should always be called if the condition for a successful pairing happened. It may be called even if there isn't currently a ongoing pairing.
    func signalPaired() {
        pairingContinuation.resume(with: .success(()))
    }

    /// Signal that the device disconnected.
    ///
    /// This method should always be called if the condition for a successful pairing happened. It may be called even if there isn't currently a ongoing pairing.
    func signalDisconnect() {
        pairingContinuation.resume(with: .failure(DevicePairingError.deviceDisconnected))
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension PairingContinuation: Sendable {}
