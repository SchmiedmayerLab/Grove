//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SpeziFoundation


/// Stores pairing state information.
@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
struct PairingContinuation {
    private let pairingContinuation: CheckedContinuation<Void, Error>

    /// Create a new pairing continuation management object.
    init(_ continuation: CheckedContinuation<Void, Error>) {
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


@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
extension PairingContinuation: Sendable {}
