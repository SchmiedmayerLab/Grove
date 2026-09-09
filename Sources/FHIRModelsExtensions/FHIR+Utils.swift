//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import ModelsR4


extension DateTime {
    /// Constructs a new `DateTime` from an `Instant`
    public init(instant: Instant) throws {
        self.init(
            date: FHIRDate(instantDate: instant.date),
            time: instant.time,
            timezone: instant.timeZone
        )
    }
}


extension FHIRDate {
    /// Constructs a new `FHIRDate` from an `InstantDate`
    public init(instantDate: InstantDate) {
        self.init(
            year: instantDate.year,
            month: instantDate.month,
            day: instantDate.day
        )
    }
}


extension Decimal {
    /// Creates a `FHIRPrimitive<FHIRDecimal>` with the value of the `Decimal`.
    public func asFHIRPrimitive() -> FHIRPrimitive<FHIRDecimal> {
        FHIRPrimitive(FHIRDecimal(self))
    }
}
