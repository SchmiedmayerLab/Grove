//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveDevices


/// Pairing view state.
@available(iOS 18, macOS 15, watchOS 11, *)
enum PairingViewState {
    /// View is currently in discovery.
    case discovery
    /// Pairing is currently in progress.
    case pairing
    /// Device is paired and shown to the user for acknowledgment.
    case paired(any PairableDevice)
    /// Pairing error occurred and is displayed to the user.
    case error(any LocalizedError)
}
