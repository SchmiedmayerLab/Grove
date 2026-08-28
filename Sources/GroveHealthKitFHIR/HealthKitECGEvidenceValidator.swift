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
            throw HealthKitConversionError.invalidECGEvidence(.invalidReportedVoltageCount(reported))
        }
        guard supplied == reported else {
            throw HealthKitConversionError.invalidECGEvidence(.voltageCountMismatch(
                reported: reported,
                supplied: supplied
            ))
        }
        guard supplied >= 2 else {
            throw HealthKitConversionError.invalidECGEvidence(.insufficientVoltageMeasurements)
        }
    }

    private static func validatedOffsets(_ points: [HealthKitECGVoltagePoint]) throws -> [Decimal] {
        let offsets = try points.enumerated().map { index, point in
            guard point.timeSinceSampleStart.isFinite, point.timeSinceSampleStart >= 0 else {
                throw HealthKitConversionError.invalidECGEvidence(.invalidOffset(index: index))
            }
            guard let exactOffset = Decimal(
                string: String(point.timeSinceSampleStart),
                locale: Locale(identifier: "en_US_POSIX")
            ) else {
                throw HealthKitConversionError.invalidECGEvidence(.invalidOffset(index: index))
            }
            return exactOffset
        }
        for index in offsets.indices.dropFirst() where offsets[index] <= offsets[index - 1] {
            throw HealthKitConversionError.invalidECGEvidence(.invalidOffset(index: index))
        }
        return offsets
    }

    private static func validatedPeriodMilliseconds(_ offsets: [Decimal]) throws -> Decimal {
        let periodSeconds = offsets[1] - offsets[0]
        for index in offsets.indices.dropFirst(2) {
            let expected = offsets[0] + Decimal(index) * periodSeconds
            guard offsets[index] == expected else {
                throw HealthKitConversionError.invalidECGEvidence(.nonUniformOffset(index: index))
            }
        }
        let periodMilliseconds = periodSeconds * 1_000
        guard periodMilliseconds > 0, !periodMilliseconds.isNaN else {
            throw HealthKitConversionError.invalidECGEvidence(.invalidOffset(index: 1))
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
            throw HealthKitConversionError.invalidECGEvidence(.invalidSamplingFrequency)
        }
        guard Decimal(frequencyHertz) * periodMilliseconds == 1_000 else {
            throw HealthKitConversionError.invalidECGEvidence(.samplingFrequencyMismatch)
        }
    }

    private static func dataString(_ points: [HealthKitECGVoltagePoint]) throws -> String {
        let values = try points.enumerated().map { index, point in
            guard point.millivolts.isFinite else {
                throw HealthKitConversionError.invalidECGEvidence(.invalidLeadVoltage(index: index))
            }
            return sampledDataDecimal(point.millivolts)
        }
        return values.joined(separator: " ")
    }

    /// Expands the standard-library round-trip representation when it uses an exponent.
    /// The result remains the exact same decimal number while satisfying the Sensor IG's
    /// plain-decimal SampledData grammar.
    private static func sampledDataDecimal(_ value: Double) -> String {
        String(groveFHIRPlainDecimal: value)
    }
}

#endif
