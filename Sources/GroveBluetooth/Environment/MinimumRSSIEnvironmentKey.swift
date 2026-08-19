//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


private struct MinimumRSSIEnvironmentKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}


extension EnvironmentValues {
    /// The minimum rssi a nearby peripheral must have to be considered nearby.
    public internal(set) var minimumRSSI: Int? {
        get {
            self[MinimumRSSIEnvironmentKey.self]
        }
        set {
            if let newValue {
                self[MinimumRSSIEnvironmentKey.self] = newValue
            }
        }
    }
}
