//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Public source-neutral record types are intentionally grouped as one contract inventory.
// swiftlint:disable file_types_order type_contents_order cyclomatic_complexity function_body_length

public import Foundation
public import GroveFHIRContract
import ModelsR4


/// Contract-level failures raised before Grove emits a Sensor FHIR resource.
public enum SensorRecordError: Error, Equatable, Sendable {
    case emptyNativeRecordID
    case emptySourceTypeIdentifier
    case incompleteCode(system: String, code: String)
    case emptySamples
    case invalidDimensions(Int)
    case sampleCountNotDivisibleByDimensions(sampleCount: Int, dimensions: Int)
    case nonFiniteSample(index: Int)
    case invalidSamplingPeriod(Double)
    case invalidEffectivePeriod
    case effectivePeriodOverflow
    case emptyECGChannels
    case mismatchedECGChannelLength(expected: Int, actual: Int, channel: Int)
    case duplicateECGLead(system: String, code: String)
    case invalidAttachmentTitle
    case invalidContentType
    case invalidRecordingFormat
    case invalidRegisteredPayload(
        format: RegisteredRecordingFormat,
        reason: RegisteredRecordingPayloadError
    )
    case emptyPayload
    case invalidSidecarPath(String)
    case payloadTooLarge(byteCount: Int)
    case rawPayloadAdmissionRequired
}


/// A complete coded concept used to name a sensor stream or ECG channel.
public struct SensorCode: Hashable, Sendable {
    public let system: String
    public let code: String
    public let display: String?

    public init(system: String, code: String, display: String? = nil) throws {
        guard !system.isEmpty,
              !code.isEmpty,
              let url = URL(string: system),
              url.scheme != nil,
              url.absoluteString == system else {
            throw SensorRecordError.incompleteCode(system: system, code: code)
        }
        self.system = system
        self.code = code
        self.display = display
    }

    var coding: Coding {
        Coding(
            code: code.asFHIRStringPrimitive(),
            display: display?.asFHIRStringPrimitive(),
            system: FHIRPrimitive(FHIRURI(stringLiteral: system))
        )
    }

    var concept: CodeableConcept {
        CodeableConcept(coding: [coding])
    }
}


/// One source-neutral, uniformly sampled numeric time series.
public struct SensorSampledDataRecord: Sendable {
    /// Adapter-local immutable record identity. It is HMACed before it reaches FHIR output.
    public let nativeRecordID: String
    public let sourceTypeIdentifier: String
    public let code: SensorCode
    public let start: Date
    public let end: Date
    public let samples: [Double]
    public let dimensions: Int
    public let periodMilliseconds: Double
    public let origin: Double
    public let unitCode: String
    public let unitDisplay: String?

    let adapterProfile: FHIRPrimitive<Canonical>?

    public init(
        nativeRecordID: String,
        sourceTypeIdentifier: String,
        code: SensorCode,
        start: Date,
        samples: [Double],
        dimensions: Int = 1,
        periodMilliseconds: Double,
        origin: Double = 0,
        unitCode: String,
        unitDisplay: String? = nil
    ) throws {
        try self.init(
            nativeRecordID: nativeRecordID,
            sourceTypeIdentifier: sourceTypeIdentifier,
            code: code,
            start: start,
            samples: samples,
            dimensions: dimensions,
            periodMilliseconds: periodMilliseconds,
            origin: origin,
            unitCode: unitCode,
            unitDisplay: unitDisplay,
            adapterProfile: nil
        )
    }

    init(
        nativeRecordID: String,
        sourceTypeIdentifier: String,
        code: SensorCode,
        start: Date,
        samples: [Double],
        dimensions: Int,
        periodMilliseconds: Double,
        origin: Double,
        unitCode: String,
        unitDisplay: String?,
        adapterProfile: FHIRPrimitive<Canonical>?
    ) throws {
        guard !nativeRecordID.isEmpty else {
            throw SensorRecordError.emptyNativeRecordID
        }
        guard !sourceTypeIdentifier.isEmpty else {
            throw SensorRecordError.emptySourceTypeIdentifier
        }
        guard !samples.isEmpty else {
            throw SensorRecordError.emptySamples
        }
        guard dimensions > 0, dimensions <= Int(Int32.max) else {
            throw SensorRecordError.invalidDimensions(dimensions)
        }
        guard samples.count.isMultiple(of: dimensions) else {
            throw SensorRecordError.sampleCountNotDivisibleByDimensions(
                sampleCount: samples.count,
                dimensions: dimensions
            )
        }
        guard periodMilliseconds.isFinite, periodMilliseconds > 0 else {
            throw SensorRecordError.invalidSamplingPeriod(periodMilliseconds)
        }
        let frameCount = samples.count / dimensions
        let durationMilliseconds = Double(frameCount - 1) * periodMilliseconds
        guard durationMilliseconds.isFinite else {
            throw SensorRecordError.effectivePeriodOverflow
        }
        let end = start.addingTimeInterval(durationMilliseconds / 1_000)
        guard end.timeIntervalSinceReferenceDate.isFinite,
              frameCount == 1 ? end == start : end > start else {
            throw SensorRecordError.effectivePeriodOverflow
        }
        guard origin.isFinite else {
            throw SensorRecordError.nonFiniteSample(index: -1)
        }
        if let index = samples.firstIndex(where: { !$0.isFinite }) {
            throw SensorRecordError.nonFiniteSample(index: index)
        }
        guard !unitCode.isEmpty else {
            throw SensorRecordError.incompleteCode(system: Canonicals.ucumSystem, code: unitCode)
        }
        self.nativeRecordID = nativeRecordID
        self.sourceTypeIdentifier = sourceTypeIdentifier
        self.code = code
        self.start = start
        self.end = end
        self.samples = samples
        self.dimensions = dimensions
        self.periodMilliseconds = periodMilliseconds
        self.origin = origin
        self.unitCode = unitCode
        self.unitDisplay = unitDisplay
        self.adapterProfile = adapterProfile
    }
}


/// One uniformly sampled ECG lead channel, expressed in millivolts.
public struct SensorECGChannel: Sendable {
    public let lead: SensorCode
    public let millivolts: [Double]
    public let originMillivolts: Double

    public init(
        lead: SensorCode,
        millivolts: [Double],
        originMillivolts: Double = 0
    ) throws {
        guard !millivolts.isEmpty else {
            throw SensorRecordError.emptySamples
        }
        guard originMillivolts.isFinite else {
            throw SensorRecordError.nonFiniteSample(index: -1)
        }
        if let index = millivolts.firstIndex(where: { !$0.isFinite }) {
            throw SensorRecordError.nonFiniteSample(index: index)
        }
        self.lead = lead
        self.millivolts = millivolts
        self.originMillivolts = originMillivolts
    }
}


/// A source-neutral ECG recording with one or more uniformly sampled lead channels.
public struct SensorECGRecord: Sendable {
    /// Adapter-local immutable record identity. It is HMACed before it reaches FHIR output.
    public let nativeRecordID: String
    public let sourceTypeIdentifier: String
    public let start: Date
    public let end: Date
    public let periodMilliseconds: Double
    public let channels: [SensorECGChannel]

    let adapterProfile: FHIRPrimitive<Canonical>?

    public init(
        nativeRecordID: String,
        sourceTypeIdentifier: String,
        start: Date,
        periodMilliseconds: Double,
        channels: [SensorECGChannel]
    ) throws {
        try self.init(
            nativeRecordID: nativeRecordID,
            sourceTypeIdentifier: sourceTypeIdentifier,
            start: start,
            periodMilliseconds: periodMilliseconds,
            channels: channels,
            adapterProfile: nil
        )
    }

    init(
        nativeRecordID: String,
        sourceTypeIdentifier: String,
        start: Date,
        periodMilliseconds: Double,
        channels: [SensorECGChannel],
        adapterProfile: FHIRPrimitive<Canonical>?
    ) throws {
        guard !nativeRecordID.isEmpty else {
            throw SensorRecordError.emptyNativeRecordID
        }
        guard !sourceTypeIdentifier.isEmpty else {
            throw SensorRecordError.emptySourceTypeIdentifier
        }
        guard periodMilliseconds.isFinite, periodMilliseconds > 0 else {
            throw SensorRecordError.invalidSamplingPeriod(periodMilliseconds)
        }
        guard !channels.isEmpty else {
            throw SensorRecordError.emptyECGChannels
        }
        let expectedSampleCount = channels[0].millivolts.count
        for (index, channel) in channels.enumerated() where channel.millivolts.count != expectedSampleCount {
            throw SensorRecordError.mismatchedECGChannelLength(
                expected: expectedSampleCount,
                actual: channel.millivolts.count,
                channel: index
            )
        }
        var leads: Set<SensorCode> = []
        for channel in channels where !leads.insert(channel.lead).inserted {
            throw SensorRecordError.duplicateECGLead(
                system: channel.lead.system,
                code: channel.lead.code
            )
        }
        let durationMilliseconds = Double(expectedSampleCount - 1) * periodMilliseconds
        guard durationMilliseconds.isFinite else {
            throw SensorRecordError.effectivePeriodOverflow
        }
        let end = start.addingTimeInterval(durationMilliseconds / 1_000)
        guard end.timeIntervalSinceReferenceDate.isFinite,
              expectedSampleCount == 1 ? end == start : end > start else {
            throw SensorRecordError.effectivePeriodOverflow
        }
        self.nativeRecordID = nativeRecordID
        self.sourceTypeIdentifier = sourceTypeIdentifier
        self.start = start
        self.end = end
        self.periodMilliseconds = periodMilliseconds
        self.channels = channels
        self.adapterProfile = adapterProfile
    }
}


/// An externally encoded or embedded native sensor recording.
///
/// Construction fails closed unless the caller supplies exactly one
/// ``SensorRawPayloadAdmission``. Grove consumes that producer-side assertion during
/// initialization and does not retain or serialize it into the FHIR graph.
public struct SensorRecordingDocument: Sendable {
    /// Where the native recording bytes travel.
    public enum Payload: Sendable {
        case inline(Data)
        case sidecar(path: String, bytes: Data)
    }

    /// Adapter-local immutable record identity. It is HMACed before it reaches FHIR output.
    public let nativeRecordID: String
    public let sourceTypeIdentifier: String
    public let type: SensorCode
    public let title: String
    public let format: RegisteredRecordingFormat
    public let contentType: String
    public let payload: Payload
    public let related: [BusinessIdentifier]

    let adapterProfile: FHIRPrimitive<Canonical>?

    public init(
        nativeRecordID: String,
        sourceTypeIdentifier: String,
        type: SensorCode,
        title: String,
        format: RegisteredRecordingFormat,
        contentType: String? = nil,
        payload: Payload,
        rawPayloadAdmission: SensorRawPayloadAdmission?,
        related: [BusinessIdentifier] = []
    ) throws {
        try self.init(
            nativeRecordID: nativeRecordID,
            sourceTypeIdentifier: sourceTypeIdentifier,
            type: type,
            title: title,
            format: format,
            contentType: contentType,
            payload: payload,
            rawPayloadAdmission: rawPayloadAdmission,
            related: related,
            adapterProfile: nil
        )
    }

    init(
        nativeRecordID: String,
        sourceTypeIdentifier: String,
        type: SensorCode,
        title: String,
        format: RegisteredRecordingFormat,
        contentType: String?,
        payload: Payload,
        rawPayloadAdmission: SensorRawPayloadAdmission?,
        related: [BusinessIdentifier],
        adapterProfile: FHIRPrimitive<Canonical>?
    ) throws {
        guard !nativeRecordID.isEmpty else {
            throw SensorRecordError.emptyNativeRecordID
        }
        guard !sourceTypeIdentifier.isEmpty else {
            throw SensorRecordError.emptySourceTypeIdentifier
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SensorRecordError.invalidAttachmentTitle
        }
        let bytes: Data
        switch payload {
        case .inline(let data), .sidecar(_, let data):
            bytes = data
        }
        guard !bytes.isEmpty else {
            throw SensorRecordError.emptyPayload
        }
        if case .sidecar(let path, _) = payload {
            guard Self.isRelativeSidecarPath(path) else {
                throw SensorRecordError.invalidSidecarPath(path)
            }
        }
        guard rawPayloadAdmission != nil else {
            throw SensorRecordError.rawPayloadAdmissionRequired
        }
        do {
            try format.validatePayload(bytes)
        } catch {
            throw SensorRecordError.invalidRegisteredPayload(format: format, reason: error)
        }
        guard let contentType = format.resolveContentType(contentType) else {
            throw SensorRecordError.invalidContentType
        }
        self.contentType = contentType
        self.nativeRecordID = nativeRecordID
        self.sourceTypeIdentifier = sourceTypeIdentifier
        self.type = type
        self.title = title
        self.format = format
        self.payload = payload
        self.related = related
        self.adapterProfile = adapterProfile
    }

    static func isRelativeSidecarPath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: {
                  $0.isEmpty || $0 == "." || $0 == ".."
              }),
              let components = URLComponents(string: path),
              components.scheme == nil,
              components.host == nil,
              components.query == nil,
              components.fragment == nil,
              components.percentEncodedPath == path else {
            return false
        }
        return true
    }
}


/// One record accepted by the source-neutral Sensor FHIR converter.
public enum SensorRecord: Sendable {
    case sampledData(SensorSampledDataRecord)
    case electrocardiogram(SensorECGRecord)
    case recordingDocument(SensorRecordingDocument)

    public var nativeRecordID: String {
        switch self {
        case .sampledData(let record): record.nativeRecordID
        case .electrocardiogram(let record): record.nativeRecordID
        case .recordingDocument(let record): record.nativeRecordID
        }
    }

    public var sourceTypeIdentifier: String {
        switch self {
        case .sampledData(let record): record.sourceTypeIdentifier
        case .electrocardiogram(let record): record.sourceTypeIdentifier
        case .recordingDocument(let record): record.sourceTypeIdentifier
        }
    }
}
