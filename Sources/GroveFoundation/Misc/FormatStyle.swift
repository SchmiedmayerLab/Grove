//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


extension Date.FormatStyle {
    /// Modifies the `FormatStyle` to use the specified calendar.
    @inlinable
    public func calendar(_ cal: Calendar) -> Self {
        var copy = self
        copy.calendar = cal
        copy.timeZone = cal.timeZone
        return copy
    }
    
    /// Modifies the `FormatStyle` to use the specified time zone.
    @inlinable
    public func timeZone(_ timeZone: TimeZone) -> Self {
        var copy = self
        copy.timeZone = timeZone
        return copy
    }
}
