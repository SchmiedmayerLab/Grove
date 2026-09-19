//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import ModelsR4


extension Observation {
    /// Sets the `Observation`'s effective date.
    @inlinable
    public mutating func setEffective(startDate: Date, endDate: Date, timeZone: TimeZone) throws {
        // Preserve each endpoint's offset through the repeated DST hour.
        let startZone = TimeZone(secondsFromGMT: timeZone.secondsFromGMT(for: startDate))! // swiftlint:disable:this force_unwrapping
        let endZone = TimeZone(secondsFromGMT: timeZone.secondsFromGMT(for: endDate))! // swiftlint:disable:this force_unwrapping
        if startDate == endDate {
            effective = .dateTime(FHIRPrimitive(try DateTime(date: startDate, timeZone: startZone)))
        } else {
            effective = .period(Period(
                end: FHIRPrimitive(try DateTime(date: endDate, timeZone: endZone)),
                start: FHIRPrimitive(try DateTime(date: startDate, timeZone: startZone))
            ))
        }
    }
    
    /// Sets the `Observation`'s issued date.
    @inlinable
    public mutating func setIssued(on date: Date) throws {
        issued = FHIRPrimitive(try Instant(date: date))
    }
}
