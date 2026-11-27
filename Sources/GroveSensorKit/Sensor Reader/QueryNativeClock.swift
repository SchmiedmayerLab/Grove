//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// A wall-clock projection of SensorKit's continuous, seconds-based native clock.
///
/// A sample-count fetch that starts without a pending batch takes a new pair and retains it with the cursor, so a
/// restart or replay of the batch it delivers projects the same callback-only dates. It never replaces a sample-owned
/// date.
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
