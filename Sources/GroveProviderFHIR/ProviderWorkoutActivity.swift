//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveFHIRContract


/// A normalized activity supported by evidence from the provider's workout type.
/// An absent or unrecognized source type must not be replaced with `other`.
public struct ProviderWorkoutActivity: RawRepresentable, Sendable, Equatable {
    public let rawValue: String

    /// Accepts only activity codes declared by the pinned workout contract.
    public init?(rawValue: String) {
        guard MeasurementCatalog.workout.allowedValues.contains(rawValue) else {
            return nil
        }
        self.rawValue = rawValue
    }
}
