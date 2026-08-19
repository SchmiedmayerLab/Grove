//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
import GroveFoundation


/// A device pairing error.
public enum DevicePairingError {
    /// Device is currently in an invalid state.
    ///
    /// For example the device is not disconnected or the advertisement was not nearby.
    case invalidState
    /// The device is busy.
    ///
    /// For example the device is already within a pairing session
    case busy
    /// The device is not in pairing mode.
    ///
    /// The ``PairableDevice/isInPairingMode`` reports that the device is not pairable.
    case notInPairingMode
    /// The device disconnected while pairing.
    ///
    /// The device disconnecting indicated that the pairing failed.
    case deviceDisconnected
}


extension DevicePairingError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidState:
            String(localized: "Invalid State")
        case .busy:
            String(localized: "Device Busy")
        case .notInPairingMode:
            String(localized: "Not Ready")
        case .deviceDisconnected:
            String(localized: "Pairing Failed")
        }
    }

    public var failureReason: String? {
        switch self {
        case .invalidState, .deviceDisconnected:
            String(localized: "Failed to pair with device. Please try again.")
        case .busy:
            String(localized: "The device is busy and failed to complete pairing.")
        case .notInPairingMode:
            String(localized: "The device was not put into pairing mode.")
        }
    }
}
