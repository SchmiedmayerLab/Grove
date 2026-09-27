//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import ModelsR4


extension FHIRDate {
    /// Creates a `DateComponents` instance with the `year`, `month`, and `day` components populated.
    ///
    /// - parameter fallback: The value that should be used for the `month` and `day` components, if the `FHIRDate` is missing the component.
    @inlinable
    public func dateComponents(missingComponentFallback fallback: Int? = 1) -> DateComponents {
        DateComponents(
            year: self.year,
            month: self.month.map(numericCast) ?? fallback,
            day: self.day.map(numericCast) ?? fallback
        )
    }
}


extension FHIRTime {
    /// Creates a `DateComponents` instance with the `hour`, `minute`, and `second` components populated.
    ///
    /// - Note: The `FHIRTime`'s `second` value will be rounded if necessary.
    @inlinable
    public func dateComponents() -> DateComponents {
        DateComponents(
            hour: Int(self.hour),
            minute: Int(self.minute),
            second: self.second.intValue
        )
    }
}


extension DateTime {
    /// Creates a `DateComponents` instance with the `timeZone`, `year`, `month`, `day`, `hour`, `minute`, and `second` components populated.
    ///
    /// - parameter dateFallback: The value that should be used for the `month` and `day` components, if the `FHIRDate` is missing the component.
    @inlinable
    public func dateComponents(missingDateComponentFallback dateFallback: Int? = 1) -> DateComponents {
        var components = self.date.dateComponents(missingComponentFallback: dateFallback)
        if let timeComps = self.time?.dateComponents() {
            components.hour = timeComps.hour
            components.minute = timeComps.minute
            components.second = timeComps.second
        }
        if let originalTimeZoneString {
            components.timeZone = TimeZone(identifier: originalTimeZoneString)
        }
        return components
    }
}
