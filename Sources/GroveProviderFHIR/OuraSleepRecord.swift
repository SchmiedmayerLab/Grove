//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// An Oura sleep session; neither the retrieval time nor the civil day substitutes for missing bedtime bounds.
public struct OuraSleepRecord: Sendable {
    /// The document's identifier.
    public let id: String
    /// The session from its bedtime start to its bedtime end, or `nil` when the source states no bounds.
    public let bedtime: ProviderInterval?
    /// The total sleep duration, in seconds.
    public var totalSleepDuration: Int?
    /// The deep sleep duration, in seconds.
    public var deepSleepDuration: Int?
    /// The REM sleep duration, in seconds.
    public var remSleepDuration: Int?
    /// The light sleep duration, in seconds.
    public var lightSleepDuration: Int?
    /// The time awake, in seconds.
    public var awakeTime: Int?
    /// The lowest heart rate, in beats per minute.
    public var lowestHeartRate: Decimal?
    /// The average respiratory rate, in breaths per minute.
    public var averageBreath: Decimal?
    /// The average heart rate variability, which the guide inventories but doesn't admit; it converts to an omission.
    public var averageHRV: Decimal?

    /// Creates a sleep record of a session with the given bounds.
    public init(id: String, bedtime: ProviderInterval?) {
        self.id = id
        self.bedtime = bedtime
    }
}
