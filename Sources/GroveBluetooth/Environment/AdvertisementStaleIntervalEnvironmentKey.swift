//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
private struct AdvertisementStaleIntervalEnvironmentKey: EnvironmentKey {
    static let defaultValue: TimeInterval? = nil
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension EnvironmentValues {
    /// The time interval after which a peripheral advertisement is considered stale if we don't hear back from the device. Minimum is 1 second.
    public internal(set) var advertisementStaleInterval: TimeInterval? {
        get {
            self[AdvertisementStaleIntervalEnvironmentKey.self]
        }
        set {
            if let newValue, newValue >= 1 {
                self[AdvertisementStaleIntervalEnvironmentKey.self] = newValue
            }
        }
    }
}
