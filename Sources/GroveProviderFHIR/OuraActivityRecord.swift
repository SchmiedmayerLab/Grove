//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// Scalar fields of an Oura daily activity document, over its source-defined activity day, from 04:00 on the named date to 04:00 on the next date.
public struct OuraActivityRecord: Sendable {
    /// The document's identifier.
    public let id: String
    /// The named activity day.
    public let day: ProviderCivilDay
    /// The step count.
    public var steps: Int?
    /// The active energy, in kilocalories.
    public var activeCalories: Decimal?
    /// Oura's equivalent walking distance in metres, converted under the shared distance measurement.
    public var equivalentWalkingDistance: Decimal?

    /// Creates an activity record without fields.
    public init(id: String, day: ProviderCivilDay) {
        self.id = id
        self.day = day
    }
}
