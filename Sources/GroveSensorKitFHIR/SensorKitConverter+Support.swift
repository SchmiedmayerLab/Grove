//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// FHIR R4 resource constructors intentionally spell out every audit and identity field together.
// swiftlint:disable multiline_literal_brackets

import CryptoKit
import FHIRModelsExtensions
import Foundation
import GroveFHIRContract
import ModelsR4


extension SensorKitConverter {
    struct ValidatedECG {
        /// The instant of the first voltage sample, where the SampledData series and the effective Period start.
        let firstSampleDate: Date
        let periodMilliseconds: Decimal
        /// The final sample's offset from `firstSampleDate`.
        let lastOffsetSeconds: Decimal
        let data: String
    }

    /// The largest disagreement between a batch's reported offset and its frequency-derived instant
    /// that still counts as the same instant.
    ///
    /// `Date` stores seconds since 2001 as a `Double`, whose resolution from 2018 through 2069
    /// (2^29 to 2^31 s) is 2^-23 to 2^-22 s, about 0.12 to 0.24 µs. A batch offset relative to the
    /// first batch is the difference of two such stored dates, so a perfectly uniform recording can
    /// miss the exact multiple of the period by about one ulp, plus any rounding in how the provider
    /// derived its chunk dates. One microsecond absorbs several ulps of that representation noise while
    /// staying about three orders of magnitude below one sample period (1.953 ms at 512 Hz), so a
    /// missing, extra, or shifted sample is still rejected.
    static let ecgTimingToleranceSeconds = Decimal(1) / 1_000_000

    static func catalogEntry(sourceToken: String) throws -> SensorKitCatalogEntry {
        guard let entry = SensorKitCatalog.current.entry(sourceToken: sourceToken) else {
            throw SensorKitRecordError.sourceTypeNotAdmitted(sourceToken)
        }
        return entry
    }

    /// An Observation's own content: its code, profiles and source-type extension. The assembler adds its
    /// identifiers, subject, device and study references.
    static func baseObservation(code: Coding, profiles: [String], sourceTypeCode: String) -> Observation {
        var observation = Observation(
            code: CodeableConcept(coding: [code]),
            status: FHIRPrimitive(.final)
        )
        observation.meta = Meta(profile: profiles.map(profile))
        observation.extension = [sourceTypeExtension(sourceTypeCode)]
        return observation
    }

    static func sourceTypeExtension(_ code: String) -> Extension {
        Extension(
            url: FHIRPrimitive(FHIRURI(
                stringLiteral: SensorKitContract.sourceTypeExtension
            )),
            value: .code(code.asFHIRStringPrimitive())
        )
    }

    static func validateECG(_ record: SensorKitECGRecord) throws -> ValidatedECG {
        let frequency = try decimal(record.frequencyHertz, field: "frequency", index: nil)
        guard frequency > 0 else {
            throw SensorKitRecordError.invalidSamplingFrequency(record.frequencyHertz)
        }
        let periodMilliseconds = Decimal(1_000) / frequency
        guard periodMilliseconds * frequency == 1_000 else {
            throw SensorKitRecordError.samplingFrequencyNotExactlyRepresentable(
                record.frequencyHertz
            )
        }
        guard let firstBatch = record.batches.first else {
            throw SensorKitRecordError.emptySamples
        }
        let periodSeconds = periodMilliseconds / 1_000
        // `startDate` can be the session's `.begin` marker, which SensorKit dates separately from the first
        // voltage chunk, so the uniform series is measured from the first batch rather than from it.
        let firstOffset = try decimal(firstBatch.offsetSeconds, field: "batchOffset", index: 0)
        var values: [String] = []
        var sampleCount = 0
        for (batchIndex, batch) in record.batches.enumerated() {
            let offset = try decimal(batch.offsetSeconds, field: "batchOffset", index: batchIndex)
            guard offset >= 0, !batch.millivolts.isEmpty else {
                throw SensorKitRecordError.invalidECGBatch(index: batchIndex)
            }
            let expectedOffset = Decimal(sampleCount) * periodSeconds
            guard (offset - firstOffset - expectedOffset).magnitude <= ecgTimingToleranceSeconds else {
                throw SensorKitRecordError.nonUniformTiming(index: sampleCount)
            }
            for voltage in batch.millivolts {
                values.append(try plainDecimal(
                    voltage,
                    field: "voltage",
                    index: sampleCount
                ))
                sampleCount += 1
            }
        }
        guard sampleCount >= 2 else {
            throw SensorKitRecordError.emptySamples
        }
        let lastOffset = Decimal(sampleCount - 1) * periodSeconds
        let duration = try decimal(record.durationSeconds, field: "duration", index: nil)
        guard (duration - firstOffset - lastOffset).magnitude <= ecgTimingToleranceSeconds else {
            throw SensorKitRecordError.inconsistentECGDuration
        }
        return ValidatedECG(
            // For a record built from a `SensorKitECGSession`, re-adding the offset recovers the first
            // chunk's own `Date` exactly, because that offset is the exact difference of two stored dates.
            firstSampleDate: record.startDate.addingTimeInterval(firstBatch.offsetSeconds),
            periodMilliseconds: periodMilliseconds,
            lastOffsetSeconds: lastOffset,
            data: values.joined(separator: " ")
        )
    }

    static func exactDateTime(
        _ date: Date,
        offsetSeconds: Decimal = 0,
        timeZone: TimeZone
    ) throws -> DateTime {
        let base = try epochDecimal(date, field: "date", index: nil)
        let target = base + offsetSeconds
        let approximate = NSDecimalNumber(decimal: target).doubleValue
        guard approximate.isFinite,
              approximate >= -62_135_596_800,
              approximate <= 253_402_300_799 else {
            throw SensorKitRecordError.nonFiniteValue(field: "date", index: nil)
        }
        var wholeSeconds = Int64(floor(approximate))
        var fraction = target - Decimal(wholeSeconds)
        if fraction < 0 {
            wholeSeconds -= 1
            fraction += 1
        } else if fraction >= 1 {
            wholeSeconds += 1
            fraction -= 1
        }
        let wholeDate = Date(timeIntervalSince1970: TimeInterval(wholeSeconds))
        // A named zone would be re-resolved from the wall clock on encoding, shifting the repeated DST hour.
        let offsetZone = timeZone.fixedOffset(at: wholeDate)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = offsetZone
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: wholeDate
        )
        guard let year = components.year,
              let month = components.month.flatMap(UInt8.init(exactly:)),
              let day = components.day.flatMap(UInt8.init(exactly:)),
              let hour = components.hour.flatMap(UInt8.init(exactly:)),
              let minute = components.minute.flatMap(UInt8.init(exactly:)),
              let second = components.second else {
            throw SensorKitRecordError.nonFiniteValue(field: "date", index: nil)
        }
        return DateTime(
            date: FHIRDate(year: year, month: month, day: day),
            time: FHIRTime(
                hour: hour,
                minute: minute,
                second: Decimal(second) + fraction
            ),
            timezone: offsetZone
        )
    }

    static func epochDecimal(_ date: Date, field: String, index: Int?) throws -> Decimal {
        try decimal(date.timeIntervalSince1970, field: field, index: index)
    }

    static func decimal(_ value: Double, field: String, index: Int?) throws -> Decimal {
        try wireDecimal(value, field: field, index: index).decimal
    }

    static func plainDecimal(_ value: Double, field: String, index: Int?) throws -> String {
        try wireDecimal(value, field: field, index: index).lexical
    }

    private static func wireDecimal(
        _ value: Double,
        field: String,
        index: Int?
    ) throws -> GroveFHIRDecimal {
        do {
            return try GroveFHIRDecimal(value)
        } catch {
            throw SensorKitRecordError.nonFiniteValue(field: field, index: index)
        }
    }

    static func period(start: Date, end: Date, timeZone: TimeZone) throws -> Period {
        guard start <= end else {
            throw SensorKitRecordError.invalidVisitPeriod
        }
        return Period(
            end: FHIRPrimitive(try exactDateTime(end, timeZone: timeZone)),
            start: FHIRPrimitive(try exactDateTime(start, timeZone: timeZone))
        )
    }

    static func recordingFormat(_ code: RegisteredRecordingFormat, entry: SensorKitCatalogEntry) throws -> Coding {
        guard entry.rawFormats.contains(code) else {
            throw SensorKitRecordError.recordingFormatNotAdmitted(code.rawValue)
        }
        // The stable code names the payload's wire grammar. Guide release versions are not part of
        // payload format Coding values.
        return Coding(
            code: code.rawValue.asFHIRStringPrimitive(),
            system: RegisteredRecordingFormat.codeSystem.asFHIRURIPrimitive()
        )
    }

    static func attachment(_ recording: SensorKitNativeRecording) throws -> Attachment {
        guard let size = Int32(exactly: recording.bytes.count) else {
            throw SensorKitConversionError.payloadTooLarge(
                byteCount: recording.bytes.count
            )
        }
        var attachment = Attachment(
            contentType: recording.contentType.asFHIRStringPrimitive(),
            hash: FHIRPrimitive(Base64Binary(with: Data(Insecure.SHA1.hash(data: recording.bytes)))),
            size: FHIRPrimitive(FHIRUnsignedInteger(size)),
            title: recording.title.asFHIRStringPrimitive()
        )
        switch recording.payload {
        case .inline(let data):
            attachment.data = FHIRPrimitive(Base64Binary(with: data))
        case .sidecar(let path, _):
            attachment.url = FHIRPrimitive(FHIRURI(stringLiteral: path))
        }
        return attachment
    }

    static func profile(_ value: String) -> FHIRPrimitive<Canonical> {
        FHIRPrimitive(Canonical(stringLiteral: value))
    }

    static func reference(_ value: String) -> Reference {
        Reference(reference: value.asFHIRStringPrimitive())
    }

    static func conceptCoding(_ code: String, _ display: String) -> Coding {
        Coding(
            code: code.asFHIRStringPrimitive(),
            display: display.asFHIRStringPrimitive(),
            system: SensorKitContract.conceptCodeSystem.asFHIRURIPrimitive()
        )
    }

    static func valueConcept(_ code: String, _ display: String) -> CodeableConcept {
        CodeableConcept(coding: [Coding(
            code: code.asFHIRStringPrimitive(),
            display: display.asFHIRStringPrimitive(),
            system: SensorKitContract.valueCodeSystem.asFHIRURIPrimitive()
        )])
    }

    static func quantity(value: Decimal, code: String, unit: String?) -> Quantity {
        Quantity(
            code: code.asFHIRStringPrimitive(),
            system: Canonicals.ucum,
            unit: unit?.asFHIRStringPrimitive(),
            value: FHIRPrimitive(FHIRDecimal(value))
        )
    }

    static func codedComponent(
        code: String,
        display: String,
        value: String,
        valueDisplay: String
    ) -> ObservationComponent {
        ObservationComponent(
            code: CodeableConcept(coding: [conceptCoding(code, display)]),
            value: .codeableConcept(valueConcept(value, valueDisplay))
        )
    }

    static func quantityComponent(
        code: String,
        display: String,
        value: Decimal,
        unitCode: String
    ) -> ObservationComponent {
        ObservationComponent(
            code: CodeableConcept(coding: [conceptCoding(code, display)]),
            value: .quantity(quantity(value: value, code: unitCode, unit: unitCode))
        )
    }

    static func periodComponent(
        code: String,
        display: String,
        interval: DateInterval,
        timeZone: TimeZone
    ) throws -> ObservationComponent {
        ObservationComponent(
            code: CodeableConcept(coding: [conceptCoding(code, display)]),
            value: .period(Period(
                end: FHIRPrimitive(try exactDateTime(interval.end, timeZone: timeZone)),
                start: FHIRPrimitive(try exactDateTime(interval.start, timeZone: timeZone))
            ))
        )
    }
}
