//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import HealthKit


@available(iOS 18, macOS 15, watchOS 11, *)
enum HealthKitTimeZoneMetadata {
    /// The metadata every sample a measurement converts to states: `HKMetadataKeyTimeZone`, naming the zone of the
    /// current calendar, which ``GroveBluetoothServices/DateTime/date`` reads a device's local time stamp in.
    ///
    /// A blood-pressure correlation and its members state the same zone: HealthKit silently drops a correlation whose
    /// zone differs from its members' (FB25571287; found on iOS 27.2, earlier versions not checked).
    static var current: [String: Any] {
        [HKMetadataKeyTimeZone: Calendar.current.timeZone.identifier]
    }
}
