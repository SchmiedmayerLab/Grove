//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
import ModelsR4


/// The SensorKit adapter's content: the outputs one record yields before the shared assembler applies the
/// event's envelope (identities, subject, devices, study context, Provenance and Bundle).
enum SensorKitConverter {
    /// What a record's content depends on beside the record itself.
    struct ContentContext {
        /// The zone the source reported its instants in; every effective bound states its offset.
        let sourceTimeZone: TimeZone
        /// Deployment/source-store namespace for the exact native `SRVisit.locationId` value.
        let visitLocationIdentifierSystem: IdentifierSystem
    }

    /// The closed adapter token every SensorKit identity preimage carries.
    static let adapterID = "sensorkit"

    /// The revision of the content this adapter drafts. Bump it whenever the bytes it emits can change for equal
    /// inputs: it enters every exporter's context fingerprint, so an event reserved under an older revision is
    /// never redelivered under the same identifier with different bytes.
    static let outputRevision: UInt = 1

    static let adapter = ExchangeAdapterContract(
        adapterID: adapterID,
        provenanceProfile: profile(SensorKitContract.conversionProvenanceProfile),
        applicationDeviceProfile: Profile.groveApplicationDevice
    )

    /// The record's outputs, the designated primary first: the structured Observation, then the raw
    /// DocumentReference, as the record's catalog row admits them. Each names the other by its source-output
    /// identity, which does not depend on the event; `nativeIdentifier` travels on the primary alone.
    static func outputs(
        of record: SensorKitRecord,
        sourceRecord: SourceRecordIdentity,
        nativeIdentifier: Identifier?,
        context: ContentContext
    ) throws -> [ExchangeOutputDraft] {
        try validateCatalogContract(record)
        let descriptors = record.discriminators
        let structuredURL = try descriptors.structured.map {
            try sourceRecord.output(role: "structured", discriminator: $0).fullURLString
        }
        let rawURL = try descriptors.raw.map {
            try sourceRecord.output(role: "native-recording", discriminator: $0).fullURLString
        }
        var outputs: [ExchangeOutputDraft] = []
        if let discriminator = descriptors.structured {
            var structured = ExchangeOutputDraft(
                role: "structured",
                discriminator: discriminator,
                resource: .observation(try buildObservation(record, rawURL: rawURL, context: context))
            )
            if case .wristTemperature(let record) = record {
                structured.trailingExtensions = [algorithmVersionExtension(record)]
            }
            outputs.append(structured)
        }
        if let discriminator = descriptors.raw, let native = record.nativeRecording {
            outputs.append(ExchangeOutputDraft(
                role: "native-recording",
                discriminator: discriminator,
                resource: .document(try buildDocument(record, native: native, relatedURL: structuredURL, context: context)),
                artifactFormatCode: native.format.rawValue
            ))
        }
        guard !outputs.isEmpty else {
            throw SensorKitConversionError.invalidIdentity("record has no catalog-admitted output")
        }
        outputs[0].clearIdentifiers = nativeIdentifier.map { [$0] } ?? []
        return outputs
    }

    /// The Device body a recording device states from its own facts; the assembler adds its identities.
    static func recordingDevice(_ device: RecordingDevice) -> ExchangeRecordingDeviceDraft {
        var resource = Device()
        resource.meta = Meta(profile: [Profile.groveRecordingDevice])
        resource.status = FHIRPrimitive(.active)
        if let name = device.name {
            resource.deviceName = [DeviceDeviceName(name: name.asFHIRStringPrimitive(), type: FHIRPrimitive(.userFriendlyName))]
        }
        resource.manufacturer = device.manufacturer?.asFHIRStringPrimitive()
        resource.modelNumber = device.modelNumber?.asFHIRStringPrimitive()
        return ExchangeRecordingDeviceDraft(device: device, resource: resource)
    }

    private static func validateCatalogContract(_ record: SensorKitRecord) throws {
        guard let entry = SensorKitCatalog.current.entry(sourceToken: record.sourceToken) else {
            throw SensorKitRecordError.sourceTypeNotAdmitted(record.sourceToken)
        }
        if case .raw = record, entry.rawProfiles.isEmpty {
            throw SensorKitRecordError.sourceTypeHasNoRawContract(record.sourceToken)
        }
    }
}


extension SensorKitRecord {
    /// Source coverage supplied for raw-only documents; structured records derive their own timing.
    var rawEffectivePeriod: DateInterval? {
        guard case .raw(let record) = self else {
            return nil
        }
        return record.effectivePeriod
    }

    var sourceRecordID: SensorKitSourceRecordID {
        switch self {
        case .rotationRate(let record): record.sourceRecordID
        case .electrocardiogram(let record): record.sourceRecordID
        case .onWrist(let record): record.sourceRecordID
        case .deviceUsage(let record): record.sourceRecordID
        case .visit(let record): record.sourceRecordID
        case .messagesUsage(let record): record.sourceRecordID
        case .phoneUsage(let record): record.sourceRecordID
        case .keyboardMetrics(let record): record.sourceRecordID
        case .sleepSession(let record): record.sourceRecordID
        case .accelerometer(let record): record.sourceRecordID
        case .wristTemperature(let record): record.sourceRecordID
        case .ppg(let record): record.sourceRecordID
        case .raw(let record): record.sourceRecordID
        }
    }

    var sourceToken: String {
        switch self {
        case .rotationRate: "SRSensor.rotationRate"
        case .electrocardiogram: "SRSensor.electrocardiogram"
        case .onWrist: "SRSensor.onWristState"
        case .deviceUsage: "SRSensor.deviceUsageReport"
        case .visit: "SRSensor.visits"
        case .messagesUsage: "SRSensor.messagesUsageReport"
        case .phoneUsage: "SRSensor.phoneUsageReport"
        case .keyboardMetrics: "SRSensor.keyboardMetrics"
        case .sleepSession: "SRSensor.sleepSessions"
        case .accelerometer: "SRSensor.accelerometer"
        case .wristTemperature: "SRSensor.wristTemperature"
        case .ppg: "SRSensor.photoplethysmogram"
        case .raw(let record): record.sourceToken
        }
    }

    /// The output discriminators the catalog row names: every raw representation is the logical
    /// `native-recording` output (sensorkit-adapter.json, `raw.outputDiscriminator`).
    var discriminators: (structured: String?, raw: String?) {
        switch self {
        case .rotationRate: ("sampled-data", nil)
        case .electrocardiogram: ("ecg-waveform", "native-recording")
        case .onWrist: ("on-wrist", nil)
        case .deviceUsage: ("device-usage-summary", "native-recording")
        case .visit: ("visit-summary", nil)
        case .messagesUsage(let record):
            ("messages-usage-summary", record.nativeRecording.map { _ in "native-recording" })
        case .phoneUsage(let record):
            ("phone-usage-summary", record.nativeRecording.map { _ in "native-recording" })
        case .keyboardMetrics: ("keyboard-metrics-summary", "native-recording")
        case .sleepSession: ("sleep-session", nil)
        case .accelerometer: ("accelerometer-recording-summary", "native-recording")
        case .wristTemperature: ("wrist-temperature-recording-summary", "native-recording")
        case .ppg: ("ppg-recording-summary", "native-recording")
        case .raw: (nil, "native-recording")
        }
    }

    var nativeRecording: SensorKitNativeRecording? {
        switch self {
        case .rotationRate, .onWrist, .visit, .sleepSession: nil
        case .electrocardiogram(let record): record.nativeRecording
        case .deviceUsage(let record): record.nativeRecording
        case .messagesUsage(let record): record.nativeRecording
        case .phoneUsage(let record): record.nativeRecording
        case .keyboardMetrics(let record): record.nativeRecording
        case .accelerometer(let record): record.nativeRecording
        case .wristTemperature(let record): record.nativeRecording
        case .ppg(let record): record.nativeRecording
        case .raw(let record): record.nativeRecording
        }
    }
}
