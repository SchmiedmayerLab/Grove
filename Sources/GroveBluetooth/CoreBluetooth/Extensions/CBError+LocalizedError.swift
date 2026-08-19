//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import CoreBluetooth
public import Foundation


extension CBError: @retroactive LocalizedError {}
extension CBATTError: @retroactive LocalizedError {}


extension CBError {
    /// The error description.
    public var errorDescription: String? {
        "CoreBluetooth Error"
    }

    /// The localized failure reason.
    public var failureReason: String? {
        localizedDescription
    }
}


extension CBATTError {
    /// The error description.
    public var errorDescription: String? {
        "CoreBluetooth ATT Error"
    }

    /// The localized failure reason.
    public var failureReason: String? {
        localizedDescription
    }
}
