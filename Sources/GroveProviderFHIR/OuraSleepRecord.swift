//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// The source sleep session; neither retrieval time nor the civil day substitutes for missing bedtime bounds.
public struct OuraSleepRecord: Sendable {
    public let id: String
    public let bedtimeStart: Date?
    public let bedtimeEnd: Date?
    /// Exact independently localized source bounds; Date convenience fields are nil for this initializer.
    public let sourceInterval: ProviderInterval?
    public var totalSleepDuration: Int?
    public var deepSleepDuration: Int?
    public var remSleepDuration: Int?
    public var lightSleepDuration: Int?
    public var awakeTime: Int?
    public var lowestHeartRate: Decimal?
    public var averageBreath: Decimal?
    /// Inventoried but not admitted by the pinned guide; retained here to return an explicit omission.
    public var averageHRV: Decimal?

    public init(id: String, bedtimeStart: Date?, bedtimeEnd: Date?) {
        self.id = id
        self.bedtimeStart = bedtimeStart
        self.bedtimeEnd = bedtimeEnd
        self.sourceInterval = nil
    }

    public init(id: String, sourceInterval: ProviderInterval) {
        self.id = id
        self.bedtimeStart = nil
        self.bedtimeEnd = nil
        self.sourceInterval = sourceInterval
    }
}


extension OuraSleepRecord {
    var measurementBounds: (effective: ProviderObservation.Effective, duration: Decimal)? {
        get throws {
            if let sourceInterval {
                return (.exactInterval(sourceInterval), sourceInterval.duration)
            }
            guard let start = bedtimeStart, let end = bedtimeEnd else {
                return nil
            }
            guard start < end else { throw ProviderConversionError.invalidInterval }
            return (.interval(start, end), Decimal(end.timeIntervalSince(start)))
        }
    }
}
