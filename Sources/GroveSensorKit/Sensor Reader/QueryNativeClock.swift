//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// A first-use wall-clock projection of SensorKit's continuous, seconds-based native clock.
/// Retaining the pair makes callback-only dates repeatable; it never replaces a sample-owned date.
struct QueryNativeClock: Hashable, Codable, Sendable {
    let nativeReferenceBits: UInt64
    let wallReference: Date

    var isValid: Bool {
        Double(bitPattern: nativeReferenceBits).isFinite && wallReference.timeIntervalSinceReferenceDate.isFinite
    }

    func date(for nativeTimestamp: Double) -> Date {
        wallReference.addingTimeInterval(nativeTimestamp - Double(bitPattern: nativeReferenceBits))
    }
}
