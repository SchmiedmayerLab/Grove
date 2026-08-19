//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


extension Text {
    static func deviceLastSeen(date: Date) -> Text {
        if Calendar.current.isDateInToday(date) {
            if #available(iOS 18, macOS 15, tvOS 18, visionOS 2, watchOS 11, *) {
                Text(
                    .currentDate,
                    format: SystemFormatStyle.DateReference(
                        to: date,
                        allowedFields: [.year, .month, .day, .hour, .minute, .second],
                        maxFieldCount: 2,
                        thresholdField: .day
                    )
                )
            } else {
                Text("at \(Text(date, style: .time))", bundle: .module)
            }
        } else if #available(iOS 18, macOS 15, tvOS 18, visionOS 2, watchOS 11, *) {
            if Calendar.current.isDateInYesterday(date) {
                Text("yesterday, \(Text(date, style: .time))", bundle: .module)
            } else {
                Text("\(Text(date, format: Date.FormatStyle(date: .complete))), \(Text(date, style: .time))", bundle: .module)
            }
        } else {
            Text("on \(Text(date, style: .date)) at \(Text(date, style: .time))", bundle: .module)
        }
    }
}

#if DEBUG
#Preview {
    Text.deviceLastSeen(date: Date.now.addingTimeInterval(-45)) // seconds
    Text.deviceLastSeen(date: Date.now.addingTimeInterval(-2 * 60)) // minutes
    Text.deviceLastSeen(date: Date.now.addingTimeInterval(-8 * 60 * 60)) // hours
    Text.deviceLastSeen(date: Date.now.addingTimeInterval(-1 * 24 * 60 * 60)) // yesterday
    Text.deviceLastSeen(date: Date.now.addingTimeInterval(-8 * 24 * 60 * 60)) // days
    Text.deviceLastSeen(date: .now.addingTimeInterval(-25 * 24 * 60 * 60)) // weeks
    Text.deviceLastSeen(date: .now.addingTimeInterval(-31 * 24 * 60 * 60)) // months
}
#endif
