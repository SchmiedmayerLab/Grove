//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// FHIR R4 resource constructors intentionally spell out every audit and identity field together.
// swiftlint:disable function_parameter_count multiline_literal_brackets

import CryptoKit
import FHIRModelsExtensions
import Foundation
import GroveFHIRContract
import ModelsR4


extension SensorKitConverter {
    struct ValidatedECG {
        let periodMilliseconds: Decimal
        let lastOffsetSeconds: Decimal
        let data: String
    }

    static func catalogEntry(sourceToken: String) throws -> SensorKitCatalogEntry {
        guard let entry = SensorKitCatalog.current.entries.first(where: {
            $0.sourceToken == sourceToken
        }) else {
            throw SensorKitRecordError.sourceTypeNotAdmitted(sourceToken)
        }
        return entry
    }

    static func baseObservation(
        code: Coding,
        profiles: [String],
        sourceTypeCode: String,
        sourceIdentifier: BusinessIdentifier,
        outputIdentifier: BusinessIdentifier,
        context: SensorKitConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> Observation {
        var observation = Observation(
            code: CodeableConcept(coding: [code]),
            status: FHIRPrimitive(.final)
        )
        observation.meta = Meta(profile: profiles.map(profile))
        observation.identifier = [sourceIdentifier.fhirIdentifier, outputIdentifier.fhirIdentifier]
        observation.subject = context.subject
        observation.device = recordingDeviceURL.map(reference)
        observation.extension = [sourceTypeExtension(sourceTypeCode)] + contextExtensions(
            context,
            converterURL: converterURL
        )
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

    static func contextExtensions(
        _ context: SensorKitConversionContext,
        converterURL: String
    ) -> [Extension] {
        var extensions = context.researchStudies.map { study in
            Extension(url: Canonicals.researchStudy, value: .reference(study))
        }
        if context.converterWasGateway {
            extensions.append(Extension(
                url: Canonicals.gatewayDevice,
                value: .reference(reference(converterURL))
            ))
        }
        return extensions
    }

    static func conversionProvenance(
        sourceIdentifier: Identifier,
        targetURLs: [String],
        converterURL: String,
        recordedAt: Date,
        timeZone: TimeZone
    ) throws -> Provenance {
        Provenance(
            activity: CodeableConcept(coding: [Coding(
                code: "transform".asFHIRStringPrimitive(),
                system: lifecycle
            )]),
            agent: [ProvenanceAgent(
                type: CodeableConcept(coding: [Coding(
                    code: "assembler".asFHIRStringPrimitive(),
                    system: participantType
                )]),
                who: reference(converterURL)
            )],
            entity: [ProvenanceEntity(
                role: FHIRPrimitive(.source),
                what: Reference(identifier: sourceIdentifier)
            )],
            meta: Meta(profile: [profile(SensorKitContract.conversionProvenanceProfile)]),
            occurred: .dateTime(FHIRPrimitive(try exactDateTime(recordedAt, timeZone: timeZone))),
            recorded: FHIRPrimitive(try exactInstant(recordedAt, timeZone: timeZone)),
            target: targetURLs.map(reference)
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
        guard !record.batches.isEmpty else {
            throw SensorKitRecordError.emptySamples
        }
        let periodSeconds = periodMilliseconds / 1_000
        var values: [String] = []
        var sampleCount = 0
        for (batchIndex, batch) in record.batches.enumerated() {
            let offset = try decimal(batch.offsetSeconds, field: "batchOffset", index: batchIndex)
            guard offset >= 0, !batch.millivolts.isEmpty else {
                throw SensorKitRecordError.invalidECGBatch(index: batchIndex)
            }
            let expectedOffset = Decimal(sampleCount) * periodSeconds
            guard offset == expectedOffset else {
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
        guard duration == lastOffset else {
            throw SensorKitRecordError.inconsistentECGDuration
        }
        return ValidatedECG(
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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
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
            timezone: timeZone
        )
    }

    static func exactInstant(_ date: Date, timeZone: TimeZone) throws -> Instant {
        try Instant(exactDateTime(date, timeZone: timeZone).description)
    }

    static func epochDecimal(_ date: Date, field: String, index: Int?) throws -> Decimal {
        try decimal(date.timeIntervalSince1970, field: field, index: index)
    }

    static func decimal(_ value: Double, field: String, index: Int?) throws -> Decimal {
        guard value.isFinite,
              let result = Decimal(
                  string: String(value),
                  locale: Locale(identifier: "en_US_POSIX")
              ) else {
            throw SensorKitRecordError.nonFiniteValue(field: field, index: index)
        }
        return result
    }

    static func plainDecimal(_ value: Double, field: String, index: Int?) throws -> String {
        _ = try decimal(value, field: field, index: index)
        return String(groveFHIRPlainDecimal: value)
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
        // The code names the payload's schema and stays stable; the release it belongs to
        // travels in Coding.version, so a guide bump never invalidates an emitted code.
        return Coding(
            code: code.rawValue.asFHIRStringPrimitive(),
            system: SensorKitContract.recordingFormatCodeSystem.asFHIRURIPrimitive(),
            version: SensorKitCatalog.current.version.asFHIRStringPrimitive()
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
            system: ucum,
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
