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
public import GroveFHIRContract
public import ModelsR4


/// Fail-closed validation errors for SensorKit adapter inputs.
public enum GroveSensorKitFHIRRecordError: Error, Equatable, Sendable {
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
    case invalidVisitPeriod
    case invalidAttachmentTitle
    case invalidContentType
    case emptyPayload
    case invalidSidecarPath(String)
    case missingProviderValue(String)
    case unsupportedProviderValue(field: String, rawValue: Int)
}


/// A producer-assigned identity for one exact SensorKit source record.
///
/// SensorKit provides no durable sample identifier. The producer must reuse this UUID only when
/// all source fields and any supplied native bytes are unchanged.
public struct GroveSensorKitSourceRecordID: Hashable, Sendable {
    public let uuid: UUID

    public init(_ uuid: UUID) {
        self.uuid = uuid
    }

    public var value: String {
        uuid.uuidString.lowercased()
    }

    public var businessIdentifier: GroveFHIRBusinessIdentifier {
        get throws {
            try GroveFHIRBusinessIdentifier(
                system: GroveSensorKitContract.sourceRecordIdentifierSystem,
                value: value
            )
        }
    }
}


/// Exact native SensorKit bytes supplied by the caller; Grove never fetches or sanitizes them.
public struct GroveSensorKitNativeRecording: Sendable {
    public enum Payload: Sendable {
        case inline(Data)
        case sidecar(path: String, bytes: Data)
    }

    public let title: String
    public let contentType: String
    public let payload: Payload
    public let format: Coding?

    public init(
        title: String,
        contentType: String,
        payload: Payload,
        admission: GroveSensorRawPayloadAdmission,
        format: Coding? = nil
    ) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GroveSensorKitFHIRRecordError.invalidAttachmentTitle
        }
        guard Self.isValidContentType(contentType) else {
            throw GroveSensorKitFHIRRecordError.invalidContentType
        }
        let bytes: Data
        switch payload {
        case .inline(let data), .sidecar(_, let data):
            bytes = data
        }
        guard !bytes.isEmpty else {
            throw GroveSensorKitFHIRRecordError.emptyPayload
        }
        if case .sidecar(let path, _) = payload, !GroveSensorRecordingDocument.isRelativeSidecarPath(path) {
            throw GroveSensorKitFHIRRecordError.invalidSidecarPath(path)
        }
        _ = admission // Producer preflight only: deliberately never retained or serialized.
        self.title = title
        self.contentType = contentType
        self.payload = payload
        self.format = format
    }

    var bytes: Data {
        switch payload {
        case .inline(let data), .sidecar(_, let data): data
        }
    }

    private static func isValidContentType(_ contentType: String) -> Bool {
        let parts = contentType.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "!#$&^_.+-"))
        return parts.count == 2 && parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy(allowed.contains)
        }
    }
}


/// One exact rotation-rate sample from SensorKit.
public struct GroveSensorKitRotationRateSample: Hashable, Sendable {
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
public struct GroveSensorKitRotationRateRecord: Sendable {
    public let sourceRecordID: GroveSensorKitSourceRecordID
    public let samples: [GroveSensorKitRotationRateSample]

    public init(sourceRecordID: GroveSensorKitSourceRecordID, samples: [GroveSensorKitRotationRateSample]) {
        self.sourceRecordID = sourceRecordID
        self.samples = samples
    }
}


public enum GroveSensorKitECGLead: String, CaseIterable, Sendable {
    case rightArmMinusLeftArm
    case leftArmMinusRightArm
}


public enum GroveSensorKitECGGuidance: String, CaseIterable, Sendable {
    case guided
    case unguided
}


/// One native SensorKit ECG batch; individual sample times are derived from the exact frequency.
public struct GroveSensorKitECGBatch: Sendable {
    public let offsetSeconds: Double
    public let millivolts: [Double]

    public init(offsetSeconds: Double, millivolts: [Double]) {
        self.offsetSeconds = offsetSeconds
        self.millivolts = millivolts
    }
}


/// A complete no-fetch SensorKit ECG hybrid input.
public struct GroveSensorKitECGRecord: Sendable {
    public let sourceRecordID: GroveSensorKitSourceRecordID
    public let startDate: Date
    public let durationSeconds: Double
    public let frequencyHertz: Double
    public let lead: GroveSensorKitECGLead
    public let guidance: GroveSensorKitECGGuidance
    public let batches: [GroveSensorKitECGBatch]
    public let nativeRecording: GroveSensorKitNativeRecording

    public init(
        sourceRecordID: GroveSensorKitSourceRecordID,
        startDate: Date,
        durationSeconds: Double,
        frequencyHertz: Double,
        lead: GroveSensorKitECGLead,
        guidance: GroveSensorKitECGGuidance,
        batches: [GroveSensorKitECGBatch],
        nativeRecording: GroveSensorKitNativeRecording
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


public enum GroveSensorKitSide: String, CaseIterable, Sendable {
    case left
    case right
}


/// A current SensorKit on-wrist state and its exact state-start instant.
public struct GroveSensorKitOnWristRecord: Sendable {
    public let sourceRecordID: GroveSensorKitSourceRecordID
    public let timestamp: Date
    public let onWrist: Bool
    public let currentStateStart: Date
    public let wristLocation: GroveSensorKitSide
    public let crownOrientation: GroveSensorKitSide

    public init(
        sourceRecordID: GroveSensorKitSourceRecordID,
        timestamp: Date,
        onWrist: Bool,
        currentStateStart: Date,
        wristLocation: GroveSensorKitSide,
        crownOrientation: GroveSensorKitSide
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
public struct GroveSensorKitDeviceUsageRecord: Sendable {
    public let sourceRecordID: GroveSensorKitSourceRecordID
    public let timestamp: Date
    public let durationSeconds: Double
    public let totalScreenWakes: Int
    public let totalUnlocks: Int
    public let totalUnlockDurationSeconds: Double
    public let nativeRecording: GroveSensorKitNativeRecording

    public init(
        sourceRecordID: GroveSensorKitSourceRecordID,
        timestamp: Date,
        durationSeconds: Double,
        totalScreenWakes: Int,
        totalUnlocks: Int,
        totalUnlockDurationSeconds: Double,
        nativeRecording: GroveSensorKitNativeRecording
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


public enum GroveSensorKitVisitLocationCategory: String, CaseIterable, Sendable {
    case home
    case work
    case school
    case gym
    case unknown
}


/// A provider-specific SensorKit visit projection. The private location identifier is not emitted.
public struct GroveSensorKitVisitRecord: Sendable {
    public let sourceRecordID: GroveSensorKitSourceRecordID
    public let locationCategory: GroveSensorKitVisitLocationCategory
    public let distanceFromHomeMeters: Double
    public let arrivalWindow: DateInterval
    public let departureWindow: DateInterval

    public init(
        sourceRecordID: GroveSensorKitSourceRecordID,
        locationCategory: GroveSensorKitVisitLocationCategory,
        distanceFromHomeMeters: Double,
        arrivalWindow: DateInterval,
        departureWindow: DateInterval
    ) {
        self.sourceRecordID = sourceRecordID
        self.locationCategory = locationCategory
        self.distanceFromHomeMeters = distanceFromHomeMeters
        self.arrivalWindow = arrivalWindow
        self.departureWindow = departureWindow
    }
}


/// An admitted raw-only SensorKit source record from the generated catalog.
public struct GroveSensorKitRawRecord: Sendable {
    public let sourceRecordID: GroveSensorKitSourceRecordID
    public let sourceToken: String
    public let nativeRecording: GroveSensorKitNativeRecording

    public init(
        sourceRecordID: GroveSensorKitSourceRecordID,
        sourceToken: String,
        nativeRecording: GroveSensorKitNativeRecording
    ) {
        self.sourceRecordID = sourceRecordID
        self.sourceToken = sourceToken
        self.nativeRecording = nativeRecording
    }
}


/// Every SensorKit output shape admitted by Grove FHIR 0.2.
public enum GroveSensorKitFHIRRecord: Sendable {
    case rotationRate(GroveSensorKitRotationRateRecord)
    case electrocardiogram(GroveSensorKitECGRecord)
    case onWrist(GroveSensorKitOnWristRecord)
    case deviceUsage(GroveSensorKitDeviceUsageRecord)
    case visit(GroveSensorKitVisitRecord)
    case raw(GroveSensorKitRawRecord)
}
