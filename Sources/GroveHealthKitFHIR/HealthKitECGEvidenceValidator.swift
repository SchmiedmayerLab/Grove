//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation


struct HealthKitECGVoltagePoint: Equatable, Sendable {
    let timeSinceSampleStart: TimeInterval
    let millivolts: Double
}


struct HealthKitECGValidatedWaveform: Equatable, Sendable {
    let firstOffsetSeconds: Decimal
    let lastOffsetSeconds: Decimal
    let periodMilliseconds: Decimal
    let data: String
}


enum HealthKitECGEvidenceValidator {
    static func validateWaveform(
        reportedCount: Int,
        samplingFrequencyHertz: Double?,
        points: [HealthKitECGVoltagePoint]
    ) throws -> HealthKitECGValidatedWaveform {
        try validateCount(reported: reportedCount, supplied: points.count)
        let offsets = try validatedOffsets(points)
        let periodMilliseconds = try validatedPeriodMilliseconds(offsets)
        try validateFrequency(samplingFrequencyHertz, periodMilliseconds: periodMilliseconds)
        return HealthKitECGValidatedWaveform(
            firstOffsetSeconds: offsets[0],
            lastOffsetSeconds: offsets[offsets.count - 1],
            periodMilliseconds: periodMilliseconds,
            data: try dataString(points)
        )
    }

    private static func validateCount(reported: Int, supplied: Int) throws {
        guard reported > 0, reported <= Int(Int32.max) else {
            throw GroveHealthKitFHIRError.invalidECGEvidence(.invalidReportedVoltageCount(reported))
        }
        guard supplied == reported else {
            throw GroveHealthKitFHIRError.invalidECGEvidence(.voltageCountMismatch(
                reported: reported,
                supplied: supplied
            ))
        }
        guard supplied >= 2 else {
            throw GroveHealthKitFHIRError.invalidECGEvidence(.insufficientVoltageMeasurements)
        }
    }

    private static func validatedOffsets(_ points: [HealthKitECGVoltagePoint]) throws -> [Decimal] {
        let offsets = try points.enumerated().map { index, point in
            guard point.timeSinceSampleStart.isFinite, point.timeSinceSampleStart >= 0 else {
                throw GroveHealthKitFHIRError.invalidECGEvidence(.invalidOffset(index: index))
            }
            guard let exactOffset = Decimal(
                string: String(point.timeSinceSampleStart),
                locale: Locale(identifier: "en_US_POSIX")
            ) else {
                throw GroveHealthKitFHIRError.invalidECGEvidence(.invalidOffset(index: index))
            }
            return exactOffset
        }
        for index in offsets.indices.dropFirst() where offsets[index] <= offsets[index - 1] {
            throw GroveHealthKitFHIRError.invalidECGEvidence(.invalidOffset(index: index))
        }
        return offsets
    }

    private static func validatedPeriodMilliseconds(_ offsets: [Decimal]) throws -> Decimal {
        let periodSeconds = offsets[1] - offsets[0]
        for index in offsets.indices.dropFirst(2) {
            let expected = offsets[0] + Decimal(index) * periodSeconds
            guard offsets[index] == expected else {
                throw GroveHealthKitFHIRError.invalidECGEvidence(.nonUniformOffset(index: index))
            }
        }
        let periodMilliseconds = periodSeconds * 1_000
        guard periodMilliseconds > 0, !periodMilliseconds.isNaN else {
            throw GroveHealthKitFHIRError.invalidECGEvidence(.invalidOffset(index: 1))
        }
        return periodMilliseconds
    }

    private static func validateFrequency(
        _ frequencyHertz: Double?,
        periodMilliseconds: Decimal
    ) throws {
        guard let frequencyHertz else {
            return
        }
        guard frequencyHertz.isFinite, frequencyHertz > 0 else {
            throw GroveHealthKitFHIRError.invalidECGEvidence(.invalidSamplingFrequency)
        }
        guard Decimal(frequencyHertz) * periodMilliseconds == 1_000 else {
            throw GroveHealthKitFHIRError.invalidECGEvidence(.samplingFrequencyMismatch)
        }
    }

    private static func dataString(_ points: [HealthKitECGVoltagePoint]) throws -> String {
        let values = try points.enumerated().map { index, point in
            guard point.millivolts.isFinite else {
                throw GroveHealthKitFHIRError.invalidECGEvidence(.invalidLeadVoltage(index: index))
            }
            return sampledDataDecimal(point.millivolts)
        }
        return values.joined(separator: " ")
    }

    /// Expands the standard-library round-trip representation when it uses an exponent.
    /// The result remains the exact same decimal number while satisfying the Sensor IG's
    /// plain-decimal SampledData grammar.
    private static func sampledDataDecimal(_ value: Double) -> String {
        guard value != 0 else {
            return "0"
        }
        let shortest = String(value)
        guard let exponentMarker = shortest.firstIndex(where: { $0 == "e" || $0 == "E" }) else {
            return shortest.hasSuffix(".0") ? String(shortest.dropLast(2)) : shortest
        }
        let mantissa = shortest[..<exponentMarker]
        let exponent = Int(shortest[shortest.index(after: exponentMarker)...]) ?? 0
        let isNegative = mantissa.first == "-"
        let unsignedMantissa = isNegative ? mantissa.dropFirst() : mantissa[...]
        let decimalPoint = unsignedMantissa.firstIndex(of: ".")
        let originalScale = decimalPoint.map { unsignedMantissa.distance(from: unsignedMantissa.startIndex, to: $0) }
            ?? unsignedMantissa.count
        let digits = unsignedMantissa.filter { $0 != "." }
        let expandedScale = originalScale + exponent
        let magnitude: String
        if expandedScale <= 0 {
            magnitude = "0." + String(repeating: "0", count: -expandedScale) + digits
        } else if expandedScale >= digits.count {
            magnitude = digits + String(repeating: "0", count: expandedScale - digits.count)
        } else {
            let insertion = digits.index(digits.startIndex, offsetBy: expandedScale)
            magnitude = digits[..<insertion] + "." + digits[insertion...]
        }
        return isNegative ? "-" + magnitude : magnitude
    }
}

#endif
