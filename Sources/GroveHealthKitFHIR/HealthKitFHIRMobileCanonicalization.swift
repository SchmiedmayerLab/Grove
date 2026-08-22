//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import ModelsR4


/// Numeric serialization rules shared by Mobile scalar and aggregate producers.
///
/// Sensor and ECG timing use their separate exact Decimal contracts and never call this helper.
enum HealthKitFHIRMobileCanonicalization {
    /// Produces a stable FHIR decimal without exposing Foundation's expanded IEEE-754 artifact.
    static func scalarDecimal(_ value: Double) throws -> FHIRPrimitive<FHIRDecimal> {
        guard value.isFinite,
              let decimal = Decimal(
                string: String(value),
                locale: Locale(identifier: "en_US_POSIX")
              ) else {
            throw GroveHealthKitFHIRError.invalidValue
        }
        return FHIRPrimitive(FHIRDecimal(decimal))
    }

    /// Rounds one Foundation `Date` to the nearest millisecond, ties to even, while retaining
    /// the source timezone's offset representation at the unrounded instant.
    static func effectiveDateTime(_ date: Date, timeZone: TimeZone) throws -> DateTime {
        let totalMilliseconds = try roundedMilliseconds(sinceEpoch: date)
        var wholeSeconds = totalMilliseconds / 1_000
        var millisecond = totalMilliseconds % 1_000
        if millisecond < 0 {
            wholeSeconds -= 1
            millisecond += 1_000
        }

        let sourceOffset = timeZone.secondsFromGMT(for: date)
        guard sourceOffset.isMultiple(of: 60),
              let fixedOffset = TimeZone(secondsFromGMT: sourceOffset) else {
            throw GroveHealthKitFHIRError.invalidValue
        }
        let lexical = try lexicalDateTime(
            wholeSeconds: wholeSeconds,
            millisecond: millisecond,
            sourceOffset: sourceOffset,
            fixedOffset: fixedOffset
        )
        do {
            return try DateTime(lexical)
        } catch {
            throw GroveHealthKitFHIRError.invalidValue
        }
    }

    private static func roundedMilliseconds(sinceEpoch date: Date) throws -> Int64 {
        let milliseconds = (date.timeIntervalSince1970 * 1_000).rounded(.toNearestOrEven)
        guard milliseconds.isFinite,
              let result = Int64(exactly: milliseconds) else {
            throw GroveHealthKitFHIRError.invalidValue
        }
        return result
    }

    private static func lexicalDateTime(
        wholeSeconds: Int64,
        millisecond: Int64,
        sourceOffset: Int,
        fixedOffset: TimeZone
    ) throws -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = fixedOffset
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date(timeIntervalSince1970: TimeInterval(wholeSeconds))
        )
        guard let year = components.year,
              (0...9_999).contains(year),
              let month = components.month,
              let day = components.day,
              let hour = components.hour,
              let minute = components.minute,
              let second = components.second else {
            throw GroveHealthKitFHIRError.invalidValue
        }

        let fraction = millisecond == 0
            ? ""
            : String(format: ".%03lld", locale: Locale(identifier: "en_US_POSIX"), millisecond)
        let offset: String
        if sourceOffset == 0 {
            offset = "Z"
        } else {
            let magnitude = abs(sourceOffset)
            offset = String(
                format: "%@%02d:%02d",
                locale: Locale(identifier: "en_US_POSIX"),
                sourceOffset < 0 ? "-" : "+",
                magnitude / 3_600,
                magnitude % 3_600 / 60
            )
        }
        let lexical = String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d%@%@",
            locale: Locale(identifier: "en_US_POSIX"),
            year,
            month,
            day,
            hour,
            minute,
            second,
            fraction,
            offset
        )
        return lexical
    }
}

#endif
