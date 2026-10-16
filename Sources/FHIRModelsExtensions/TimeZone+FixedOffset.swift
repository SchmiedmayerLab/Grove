//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


extension TimeZone {
    /// A fixed-offset zone carrying this zone's UTC offset at `date`.
    ///
    /// FHIRModels' `DateTime` keeps the zone it is given and re-derives the offset from its wall-clock components
    /// when it is serialized. In the repeated hour of a daylight-saving fall-back transition that lookup resolves to the
    /// first occurrence, so an instant in the second occurrence would be written one hour early.
    /// Build FHIR date-times with the returned zone instead of a named zone so the serialized offset stays tied to `date`.
    ///
    /// - Returns: A zone whose offset is `secondsFromGMT(for: date)`, or `self` if Foundation cannot represent that offset.
    public func fixedOffset(at date: Date) -> TimeZone {
        TimeZone(secondsFromGMT: secondsFromGMT(for: date)) ?? self
    }
}
