//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// SensorKit's public axis names intentionally match Apple's x/y/z vocabulary, and the file keeps
// closely related public input records together so the complete no-fetch facade is readable in one place.
// swiftlint:disable file_types_order identifier_name type_contents_order

public import Foundation


/// Fail-closed validation errors for SensorKit adapter inputs.
public enum SensorKitRecordError: Error, Equatable, Sendable {
    case sourceTypeNotAdmitted(String)
    case sourceTypeHasNoRawContract(String)
    case emptySamples
    case nonFiniteValue(field: String, index: Int?)
    case nonUniformTiming(index: Int)
    case invalidSamplingFrequency(Double)
    case samplingFrequencyNotExactlyRepresentable(Double)
    case invalidECGBatch(index: Int)
    case inconsistentECGDuration
    case invalidCurrentStatePeriod
    case invalidDeviceUsagePeriod
    case invalidDeviceUsageCount(field: String, value: Int)
    case invalidReportDuration(field: String)
    case invalidReportCount(field: String, value: Int)
    case invalidTypingSpeed(Double)
    case invalidVisitPeriod
    case invalidAttachmentTitle
    case invalidContentType
    case invalidRecordingFormat
    case recordingFormatNotAdmitted(String)
    case invalidRecordingPeriod
    case invalidRegisteredPayload(
        format: RegisteredRecordingFormat,
        reason: RegisteredRecordingPayloadError
    )
    case emptyPayload
    case invalidSidecarPath(String)
    case missingProviderValue(String)
    case unsupportedProviderValue(field: String, rawValue: Int)
}


/// A producer-assigned identity for one exact SensorKit source record.
///
/// SensorKit provides no durable sample identifier. The producer must assign this UUID from a
/// persisted acquisition-batch coordinate plus record ordinal, and reuse it only for that same
/// coordinate after verifying the retried source fields/native bytes against the persisted digest.
/// Byte-identical records delivered at distinct coordinates require distinct UUIDs so multiplicity
/// is never collapsed by content.
public struct SensorKitSourceRecordID: Hashable, Sendable {
    public let uuid: UUID

    public init(_ uuid: UUID) {
        self.uuid = uuid
    }

    public var value: String {
        uuid.uuidString.lowercased()
    }
}


/// Exact native SensorKit bytes supplied by the caller; Grove never fetches or sanitizes them.
public struct SensorKitNativeRecording: Sendable {
    public enum Payload: Sendable {
        case inline(Data)
        case sidecar(path: String, bytes: Data)
    }

    public let title: String
    public let format: RegisteredRecordingFormat
    public let contentType: String
    public let payload: Payload

    public init(
        title: String,
        format: RegisteredRecordingFormat,
        contentType: String? = nil,
        payload: Payload,
        admission: SensorRawPayloadAdmission
    ) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SensorKitRecordError.invalidAttachmentTitle
        }
        let bytes: Data
        switch payload {
        case .inline(let data), .sidecar(_, let data):
            bytes = data
        }
        guard !bytes.isEmpty else {
            throw SensorKitRecordError.emptyPayload
        }
        if case .sidecar(let path, _) = payload, !SensorRecordingDocument.isRelativeSidecarPath(path) {
            throw SensorKitRecordError.invalidSidecarPath(path)
        }
        do {
            try format.validatePayload(bytes)
        } catch {
            throw SensorKitRecordError.invalidRegisteredPayload(format: format, reason: error)
        }
        guard let contentType = format.resolveContentType(contentType) else {
            throw SensorKitRecordError.invalidContentType
        }
        self.contentType = contentType
        _ = admission // Producer preflight only: deliberately never retained or serialized.
        self.title = title
        self.format = format
        self.payload = payload
    }

    var bytes: Data {
        switch payload {
        case .inline(let data), .sidecar(_, let data): data
        }
    }
}


/// Where Grove places bytes it generates for a registered recording.
public enum SensorKitRecordingLocation: Sendable {
    case inline
    case sidecar(path: String)

    func payload(bytes: Data) -> SensorKitNativeRecording.Payload {
        switch self {
        case .inline: .inline(bytes)
        case .sidecar(let path): .sidecar(path: path, bytes: bytes)
        }
    }
}


/// One exact rotation-rate sample from SensorKit.
public struct SensorKitRotationRateSample: Hashable, Sendable {
    public let timestamp: Date
    public let x: Double
    public let y: Double
    public let z: Double

    public init(timestamp: Date, x: Double, y: Double, z: Double) {
        self.timestamp = timestamp
        self.x = x
        self.y = y
        self.z = z
    }
}


/// A complete uniformly timed SensorKit rotation-rate source record.
public struct SensorKitRotationRateRecord: Sendable {
    public let sourceRecordID: SensorKitSourceRecordID
    public let samples: [SensorKitRotationRateSample]

    public init(sourceRecordID: SensorKitSourceRecordID, samples: [SensorKitRotationRateSample]) {
        self.sourceRecordID = sourceRecordID
        self.samples = samples
    }
}


public enum SensorKitECGLead: String, CaseIterable, Sendable {
    case rightArmMinusLeftArm
    case leftArmMinusRightArm
}


public enum SensorKitECGGuidance: String, CaseIterable, Sendable {
    case guided
    case unguided
}


/// One native SensorKit ECG batch; individual sample times are derived from the exact frequency.
public struct SensorKitECGBatch: Sendable {
    public let offsetSeconds: Double
    public let millivolts: [Double]

    public init(offsetSeconds: Double, millivolts: [Double]) {
        self.offsetSeconds = offsetSeconds
        self.millivolts = millivolts
    }
}


/// A complete no-fetch SensorKit ECG hybrid input.
public struct SensorKitECGRecord: Sendable {
    public let sourceRecordID: SensorKitSourceRecordID
    public let startDate: Date
    public let durationSeconds: Double
    public let frequencyHertz: Double
    public let lead: SensorKitECGLead
    public let guidance: SensorKitECGGuidance
    public let batches: [SensorKitECGBatch]
    public let nativeRecording: SensorKitNativeRecording

    public init(
        sourceRecordID: SensorKitSourceRecordID,
        startDate: Date,
        durationSeconds: Double,
        frequencyHertz: Double,
        lead: SensorKitECGLead,
        guidance: SensorKitECGGuidance,
        batches: [SensorKitECGBatch],
        nativeRecording: SensorKitNativeRecording
    ) {
        self.sourceRecordID = sourceRecordID
        self.startDate = startDate
        self.durationSeconds = durationSeconds
        self.frequencyHertz = frequencyHertz
        self.lead = lead
        self.guidance = guidance
        self.batches = batches
        self.nativeRecording = nativeRecording
    }
}


public enum SensorKitSide: String, CaseIterable, Sendable {
    case left
    case right
}


/// A current SensorKit on-wrist state and its exact state-start instant.
public struct SensorKitOnWristRecord: Sendable {
    public let sourceRecordID: SensorKitSourceRecordID
    public let timestamp: Date
    public let onWrist: Bool
    public let currentStateStart: Date
    public let wristLocation: SensorKitSide
    public let crownOrientation: SensorKitSide

    public init(
        sourceRecordID: SensorKitSourceRecordID,
        timestamp: Date,
        onWrist: Bool,
        currentStateStart: Date,
        wristLocation: SensorKitSide,
        crownOrientation: SensorKitSide
    ) {
        self.sourceRecordID = sourceRecordID
        self.timestamp = timestamp
        self.onWrist = onWrist
        self.currentStateStart = currentStateStart
        self.wristLocation = wristLocation
        self.crownOrientation = crownOrientation
    }
}


/// The lossless structured fields from a SensorKit device-usage report plus exact native bytes.
public struct SensorKitDeviceUsageRecord: Sendable {
    public let sourceRecordID: SensorKitSourceRecordID
    public let timestamp: Date
    public let durationSeconds: Double
    public let totalScreenWakes: Int
    public let totalUnlocks: Int
    public let totalUnlockDurationSeconds: Double
    public let nativeRecording: SensorKitNativeRecording

    public init(
        sourceRecordID: SensorKitSourceRecordID,
        timestamp: Date,
        durationSeconds: Double,
        totalScreenWakes: Int,
        totalUnlocks: Int,
        totalUnlockDurationSeconds: Double,
        nativeRecording: SensorKitNativeRecording
    ) {
        self.sourceRecordID = sourceRecordID
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.totalScreenWakes = totalScreenWakes
        self.totalUnlocks = totalUnlocks
        self.totalUnlockDurationSeconds = totalUnlockDurationSeconds
        self.nativeRecording = nativeRecording
    }
}


public enum SensorKitVisitLocationCategory: String, CaseIterable, Sendable {
    case home
    case work
    case school
    case gym
    case unknown
}


/// A platform-exclusive SensorKit visit projection.
public struct SensorKitVisitRecord: Sendable {
    public let sourceRecordID: SensorKitSourceRecordID
    public let locationCategory: SensorKitVisitLocationCategory
    public let distanceFromHomeMeters: Double
    public let arrivalWindow: DateInterval
    public let departureWindow: DateInterval
    /// SensorKit's own identifier for the place visited, when the caller supplies it.
    ///
    /// Conversion preserves its canonical lowercase UUID under the caller's governed
    /// deployment/source-store namespace on an identifier-only logical `Location` focus.
    public let locationID: UUID?

    public init(
        sourceRecordID: SensorKitSourceRecordID,
        locationCategory: SensorKitVisitLocationCategory,
        distanceFromHomeMeters: Double,
        arrivalWindow: DateInterval,
        departureWindow: DateInterval,
        locationID: UUID? = nil
    ) {
        self.sourceRecordID = sourceRecordID
        self.locationCategory = locationCategory
        self.distanceFromHomeMeters = distanceFromHomeMeters
        self.arrivalWindow = arrivalWindow
        self.departureWindow = departureWindow
        self.locationID = locationID
    }
}


/// An admitted raw-only SensorKit source record from the generated catalog.
public struct SensorKitRawRecord: Sendable {
    public let sourceRecordID: SensorKitSourceRecordID
    public let sourceToken: String
    /// Exact source coverage of the native recording.
    public let effectivePeriod: DateInterval
    public let nativeRecording: SensorKitNativeRecording

    public init(
        sourceRecordID: SensorKitSourceRecordID,
        sourceToken: String,
        effectivePeriod: DateInterval,
        nativeRecording: SensorKitNativeRecording
    ) throws {
        guard effectivePeriod.start.timeIntervalSinceReferenceDate.isFinite,
              effectivePeriod.end.timeIntervalSinceReferenceDate.isFinite,
              effectivePeriod.duration.isFinite,
              effectivePeriod.duration >= 0 else {
            throw SensorKitRecordError.invalidRecordingPeriod
        }
        self.sourceRecordID = sourceRecordID
        self.sourceToken = sourceToken
        self.effectivePeriod = effectivePeriod
        self.nativeRecording = nativeRecording
    }
}


/// Every SensorKit output shape admitted by the Grove FHIR Implementation Guides.
public enum SensorKitRecord: Sendable {
    case rotationRate(SensorKitRotationRateRecord)
    case electrocardiogram(SensorKitECGRecord)
    case onWrist(SensorKitOnWristRecord)
    case deviceUsage(SensorKitDeviceUsageRecord)
    case visit(SensorKitVisitRecord)
    case messagesUsage(SensorKitMessagesUsageRecord)
    case phoneUsage(SensorKitPhoneUsageRecord)
    case keyboardMetrics(SensorKitKeyboardMetricsRecord)
    case sleepSession(SensorKitSleepSessionRecord)
    case accelerometer(SensorKitAccelerometerRecord)
    case wristTemperature(SensorKitWristTemperatureRecord)
    case ppg(SensorKitPPGRecord)
    case raw(SensorKitRawRecord)
}
