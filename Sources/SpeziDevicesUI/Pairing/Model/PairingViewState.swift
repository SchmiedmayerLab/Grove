//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SpeziDevices


/// Pairing view state.
@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
enum PairingViewState {
    /// View is currently in discovery.
    case discovery
    /// Pairing is currently in progress.
    case pairing
    /// Device is paired and shown to the user for acknowledgment.
    case paired(any PairableDevice)
    /// Pairing error occurred and is displayed to the user.
    case error(LocalizedError)
}
