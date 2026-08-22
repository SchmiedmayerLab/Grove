//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// FHIR R4 initializers expose profile cardinalities directly; keeping those fields adjacent makes
// the clinical projection auditable against the IG even when a builder exceeds generic style limits.
// swiftlint:disable function_body_length function_parameter_count

import Foundation
import GroveFHIRContract
import ModelsR4


extension GroveSensorKitFHIRConverter {
    static func summaryObservation(
        _ record: GroveSensorKitFHIRRecord,
        sourceIdentifier: GroveFHIRBusinessIdentifier,
        outputIdentifier: GroveFHIRBusinessIdentifier,
        rawURL: String?,
        context: GroveSensorKitFHIRConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> Observation {
        switch record {
        case .messagesUsage(let record):
            try messagesUsageObservation(
                record,
                sourceIdentifier: sourceIdentifier,
                outputIdentifier: outputIdentifier,
                rawURL: rawURL,
                context: context,
                recordingDeviceURL: recordingDeviceURL,
                converterURL: converterURL
            )
        case .phoneUsage(let record):
            try phoneUsageObservation(
                record,
                sourceIdentifier: sourceIdentifier,
                outputIdentifier: outputIdentifier,
                rawURL: rawURL,
                context: context,
                recordingDeviceURL: recordingDeviceURL,
                converterURL: converterURL
            )
        case .keyboardMetrics(let record):
            try keyboardMetricsObservation(
                record,
                sourceIdentifier: sourceIdentifier,
                outputIdentifier: outputIdentifier,
                rawURL: try requiredRawURL(rawURL, sourceToken: "SRSensor.keyboardMetrics"),
                context: context,
                recordingDeviceURL: recordingDeviceURL,
                converterURL: converterURL
            )
        case .sleepSession(let record):
            try sleepSessionObservation(
                record,
                sourceIdentifier: sourceIdentifier,
                outputIdentifier: outputIdentifier,
                context: context,
                recordingDeviceURL: recordingDeviceURL,
                converterURL: converterURL
            )
        case .accelerometer(let record):
            try accelerometerObservation(
                record,
                sourceIdentifier: sourceIdentifier,
                outputIdentifier: outputIdentifier,
                rawURL: try requiredRawURL(rawURL, sourceToken: "SRSensor.accelerometer"),
                context: context,
                recordingDeviceURL: recordingDeviceURL,
                converterURL: converterURL
            )
        case .ppg(let record):
            try ppgObservation(
                record,
                sourceIdentifier: sourceIdentifier,
                outputIdentifier: outputIdentifier,
                rawURL: try requiredRawURL(rawURL, sourceToken: "SRSensor.photoplethysmogram"),
                context: context,
                recordingDeviceURL: recordingDeviceURL,
                converterURL: converterURL
            )
        case .rotationRate, .electrocardiogram, .onWrist, .deviceUsage, .visit, .raw:
            throw GroveSensorKitFHIRRecordError.sourceTypeNotAdmitted(record.sourceToken)
        }
    }

    private static func messagesUsageObservation(
        _ record: GroveSensorKitMessagesUsageRecord,
        sourceIdentifier: GroveFHIRBusinessIdentifier,
        outputIdentifier: GroveFHIRBusinessIdentifier,
        rawURL: String?,
        context: GroveSensorKitFHIRConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> Observation {
        let duration = try reportDuration(record.durationSeconds)
        let entry = try catalogEntry(sourceToken: "SRSensor.messagesUsageReport")
        var observation = try baseObservation(
            code: conceptCoding("messages-usage-summary", "Messages usage summary"),
            profiles: entry.structuredProfiles,
            sourceTypeCode: entry.sourceTypeCode,
            sourceIdentifier: sourceIdentifier,
            outputIdentifier: outputIdentifier,
            context: context,
            recordingDeviceURL: recordingDeviceURL,
            converterURL: converterURL
        )
        observation.effective = .period(try reportPeriod(
            record.timestamp,
            duration: duration,
            timeZone: context.sourceTimeZone
        ))
        observation.component = [
            try countComponent("incoming-messages", "Incoming messages", record.totalIncomingMessages),
            try countComponent("outgoing-messages", "Outgoing messages", record.totalOutgoingMessages),
            try countComponent("unique-contacts", "Unique contacts", record.totalUniqueContacts)
        ]
        observation.derivedFrom = rawURL.map { [reference($0)] }
        return observation
    }

    private static func phoneUsageObservation(
        _ record: GroveSensorKitPhoneUsageRecord,
        sourceIdentifier: GroveFHIRBusinessIdentifier,
        outputIdentifier: GroveFHIRBusinessIdentifier,
        rawURL: String?,
        context: GroveSensorKitFHIRConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> Observation {
        let duration = try reportDuration(record.durationSeconds)
        let callDuration = try nonNegativeDuration(
            record.totalPhoneCallDurationSeconds,
            field: "totalPhoneCallDuration"
        )
        let entry = try catalogEntry(sourceToken: "SRSensor.phoneUsageReport")
        var observation = try baseObservation(
            code: conceptCoding("phone-usage-summary", "Phone usage summary"),
            profiles: entry.structuredProfiles,
            sourceTypeCode: entry.sourceTypeCode,
            sourceIdentifier: sourceIdentifier,
            outputIdentifier: outputIdentifier,
            context: context,
            recordingDeviceURL: recordingDeviceURL,
            converterURL: converterURL
        )
        observation.effective = .period(try reportPeriod(
            record.timestamp,
            duration: duration,
            timeZone: context.sourceTimeZone
        ))
        observation.value = .quantity(quantity(value: callDuration, code: "s", unit: "seconds"))
        observation.component = [
            try countComponent("incoming-calls", "Incoming calls", record.totalIncomingCalls),
            try countComponent("outgoing-calls", "Outgoing calls", record.totalOutgoingCalls),
            try countComponent("unique-contacts", "Unique contacts", record.totalUniqueContacts)
        ]
        observation.derivedFrom = rawURL.map { [reference($0)] }
        return observation
    }

    private static func keyboardMetricsObservation(
        _ record: GroveSensorKitKeyboardMetricsRecord,
        sourceIdentifier: GroveFHIRBusinessIdentifier,
        outputIdentifier: GroveFHIRBusinessIdentifier,
        rawURL: String,
        context: GroveSensorKitFHIRConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> Observation {
        let duration = try reportDuration(record.durationSeconds)
        let typingDuration = try nonNegativeDuration(
            record.totalTypingDurationSeconds,
            field: "totalTypingDuration"
        )
        guard record.typingSpeed.isFinite, record.typingSpeed >= 0 else {
            throw GroveSensorKitFHIRRecordError.invalidTypingSpeed(record.typingSpeed)
        }
        let entry = try catalogEntry(sourceToken: "SRSensor.keyboardMetrics")
        var observation = try baseObservation(
            code: conceptCoding("keyboard-metrics-summary", "Keyboard metrics summary"),
            profiles: entry.structuredProfiles,
            sourceTypeCode: entry.sourceTypeCode,
            sourceIdentifier: sourceIdentifier,
            outputIdentifier: outputIdentifier,
            context: context,
            recordingDeviceURL: recordingDeviceURL,
            converterURL: converterURL
        )
        observation.effective = .period(try reportPeriod(
            record.timestamp,
            duration: duration,
            timeZone: context.sourceTimeZone
        ))
        observation.value = .quantity(quantity(value: typingDuration, code: "s", unit: "seconds"))
        observation.component = [
            try countComponent("total-words", "Total words", record.totalWords),
            try countComponent("total-altered-words", "Total altered words", record.totalAlteredWords),
            try countComponent("total-taps", "Total taps", record.totalTaps),
            try countComponent("total-deletes", "Total deletes", record.totalDeletes),
            try countComponent("total-emojis", "Total emojis", record.totalEmojis),
            try countComponent("total-autocorrections", "Total autocorrections", record.totalAutocorrections),
            try countComponent("total-pauses", "Total pauses", record.totalPauses),
            try countComponent("total-typing-episodes", "Total typing episodes", record.totalTypingEpisodes),
            quantityComponent(
                code: "typing-speed",
                display: "Typing speed",
                value: try decimal(record.typingSpeed, field: "typingSpeed", index: nil),
                unitCode: "/s"
            )
        ]
        observation.derivedFrom = [reference(rawURL)]
        return observation
    }

    private static func sleepSessionObservation(
        _ record: GroveSensorKitSleepSessionRecord,
        sourceIdentifier: GroveFHIRBusinessIdentifier,
        outputIdentifier: GroveFHIRBusinessIdentifier,
        context: GroveSensorKitFHIRConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> Observation {
        let entry = try catalogEntry(sourceToken: "SRSensor.sleepSessions")
        var observation = try baseObservation(
            code: conceptCoding("sleep-session", "Sleep session"),
            profiles: entry.structuredProfiles,
            sourceTypeCode: entry.sourceTypeCode,
            sourceIdentifier: sourceIdentifier,
            outputIdentifier: outputIdentifier,
            context: context,
            recordingDeviceURL: recordingDeviceURL,
            converterURL: converterURL
        )
        observation.effective = .period(try period(
            start: record.session.start,
            end: record.session.end,
            timeZone: context.sourceTimeZone
        ))
        observation.value = .quantity(quantity(
            value: try nonNegativeDuration(record.session.duration, field: "sleepSessionDuration"),
            code: "s",
            unit: "seconds"
        ))
        return observation
    }

    private static func accelerometerObservation(
        _ record: GroveSensorKitAccelerometerRecord,
        sourceIdentifier: GroveFHIRBusinessIdentifier,
        outputIdentifier: GroveFHIRBusinessIdentifier,
        rawURL: String,
        context: GroveSensorKitFHIRConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> Observation {
        let entry = try catalogEntry(sourceToken: "SRSensor.accelerometer")
        var observation = try baseObservation(
            code: conceptCoding("accelerometer-recording-summary", "Accelerometer recording summary"),
            profiles: entry.structuredProfiles,
            sourceTypeCode: entry.sourceTypeCode,
            sourceIdentifier: sourceIdentifier,
            outputIdentifier: outputIdentifier,
            context: context,
            recordingDeviceURL: recordingDeviceURL,
            converterURL: converterURL
        )
        observation.effective = .period(try period(
            start: record.coverage.start,
            end: record.coverage.end,
            timeZone: context.sourceTimeZone
        ))
        observation.component = [
            try countComponent("sample-count", "Sample count", record.sampleCount),
            try countComponent("batch-count", "Batch count", record.batchCount)
        ]
        observation.derivedFrom = [reference(rawURL)]
        return observation
    }

    private static func ppgObservation(
        _ record: GroveSensorKitPPGRecord,
        sourceIdentifier: GroveFHIRBusinessIdentifier,
        outputIdentifier: GroveFHIRBusinessIdentifier,
        rawURL: String,
        context: GroveSensorKitFHIRConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> Observation {
        let entry = try catalogEntry(sourceToken: "SRSensor.photoplethysmogram")
        var observation = try baseObservation(
            code: conceptCoding("ppg-recording-summary", "PPG recording summary"),
            profiles: entry.structuredProfiles,
            sourceTypeCode: entry.sourceTypeCode,
            sourceIdentifier: sourceIdentifier,
            outputIdentifier: outputIdentifier,
            context: context,
            recordingDeviceURL: recordingDeviceURL,
            converterURL: converterURL
        )
        observation.effective = .period(try period(
            start: record.coverage.start,
            end: record.coverage.end,
            timeZone: context.sourceTimeZone
        ))
        observation.component = [
            try countComponent("record-count", "Record count", record.recordCount),
            try countComponent("optical-sample-count", "Optical sample count", record.opticalSampleCount),
            try countComponent("accelerometer-sample-count", "Accelerometer sample count", record.accelerometerSampleCount)
        ]
        observation.derivedFrom = [reference(rawURL)]
        return observation
    }

    private static func requiredRawURL(_ rawURL: String?, sourceToken: String) throws -> String {
        guard let rawURL else {
            throw GroveSensorKitFHIRRecordError.sourceTypeHasNoRawContract(sourceToken)
        }
        return rawURL
    }

    private static func reportDuration(_ value: Double) throws -> Decimal {
        guard value.isFinite, value > 0 else {
            throw GroveSensorKitFHIRRecordError.invalidReportDuration(field: "duration")
        }
        return try decimal(value, field: "duration", index: nil)
    }

    private static func nonNegativeDuration(_ value: Double, field: String) throws -> Decimal {
        guard value.isFinite, value >= 0 else {
            throw GroveSensorKitFHIRRecordError.invalidReportDuration(field: field)
        }
        return try decimal(value, field: field, index: nil)
    }

    private static func reportPeriod(_ start: Date, duration: Decimal, timeZone: TimeZone) throws -> Period {
        Period(
            end: FHIRPrimitive(try exactDateTime(start, offsetSeconds: duration, timeZone: timeZone)),
            start: FHIRPrimitive(try exactDateTime(start, timeZone: timeZone))
        )
    }

    private static func countComponent(_ code: String, _ display: String, _ value: Int) throws -> ObservationComponent {
        guard value >= 0, Int32(exactly: value) != nil else {
            throw GroveSensorKitFHIRRecordError.invalidReportCount(field: code, value: value)
        }
        return quantityComponent(code: code, display: display, value: Decimal(value), unitCode: "{count}")
    }
}
