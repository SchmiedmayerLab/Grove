//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The private Codable envelopes follow the public preparation facade in this platform bridge.
// swiftlint:disable file_types_order type_contents_order

#if os(iOS)
public import Foundation
public import GroveSensorKit
public import SensorKit


/// A structured SensorKit value prepared for stable retry checking and Grove conversion.
///
/// Grove owns the evidence encoding because it must remain identical across clients. The client
/// owns persistence and chooses whether generated native bytes are attached inline or as a sidecar.
public struct SensorKitPreparedStructuredRecord: Sendable {
    private enum Value: Sendable {
        case visit(SRVisit.SafeRepresentation)
        case onWrist(SensorKitOnWristEventSample)
        case deviceUsage(SRDeviceUsageReport.SafeRepresentation)
        case electrocardiogram(SensorKitECGSession)
    }

    private let value: Value
    public let retryEvidence: Data
    public let nativePayload: Data?

    public init(visit: SRVisit.SafeRepresentation) throws {
        var writer = RecordingBinaryWriter()
        try writer.writeFloat64(visit.timestamp.timeIntervalSince1970)
        writer.writeString(visit.locationId.uuidString.lowercased())
        try writer.writeFloat64(visit.distanceFromHome)
        try writer.writeFloat64(visit.arrivalDateInterval.start.timeIntervalSince1970)
        try writer.writeFloat64(visit.arrivalDateInterval.end.timeIntervalSince1970)
        try writer.writeFloat64(visit.departureDateInterval.start.timeIntervalSince1970)
        try writer.writeFloat64(visit.departureDateInterval.end.timeIntervalSince1970)
        writer.writeVarint(Int64(visit.locationCategory.rawValue))
        self.value = .visit(visit)
        self.retryEvidence = writer.data()
        self.nativePayload = nil
    }

    @available(iOS 18, *)
    public init(onWrist sample: SensorKitOnWristEventSample) throws {
        var writer = RecordingBinaryWriter()
        try writer.writeFloat64(sample.timestamp.timeIntervalSince1970)
        writer.writeBoolean(sample.onWrist)
        writer.writeVarint(Int64(sample.wristLocation.rawValue))
        writer.writeVarint(Int64(sample.crownOrientation.rawValue))
        try writer.writeOptionalFloat64(sample.onWristDate?.timeIntervalSince1970)
        try writer.writeOptionalFloat64(sample.offWristDate?.timeIntervalSince1970)
        self.value = .onWrist(sample)
        self.retryEvidence = writer.data()
        self.nativePayload = nil
    }

    @available(iOS 18, *)
    public init(deviceUsage report: SRDeviceUsageReport.SafeRepresentation) throws {
        let payload = try Self.encodeJSON(DeviceUsageEvidence(report))
        self.value = .deviceUsage(report)
        self.retryEvidence = payload
        self.nativePayload = payload
    }

    @available(iOS 17.4, *)
    public init(electrocardiogram session: SensorKitECGSession) throws {
        let payload = try Self.encodeJSON(ECGEvidence(session))
        self.value = .electrocardiogram(session)
        self.retryEvidence = payload
        self.nativePayload = payload
    }

    /// Creates the Grove record. Native evidence is required exactly when `nativePayload` is non-nil.
    public func sensorKitRecord(
        sourceRecordID: SensorKitSourceRecordID,
        nativeRecording: SensorKitNativeRecording? = nil
    ) throws -> SensorKitRecord {
        switch value {
        case .visit(let visit):
            guard nativeRecording == nil else {
                throw SensorKitRecordError.invalidRecordingFormat
            }
            return .visit(try SensorKitVisitRecord(
                sourceRecordID: sourceRecordID,
                visit: visit,
                locationID: visit.locationId
            ))
        case .onWrist(let sample):
            guard nativeRecording == nil else {
                throw SensorKitRecordError.invalidRecordingFormat
            }
            return .onWrist(try SensorKitOnWristRecord(
                sourceRecordID: sourceRecordID,
                sample: sample
            ))
        case .deviceUsage(let report):
            guard let nativeRecording else {
                throw SensorKitRecordError.missingProviderValue("deviceUsage.nativeRecording")
            }
            return .deviceUsage(SensorKitDeviceUsageRecord(
                sourceRecordID: sourceRecordID,
                report: report,
                nativeRecording: nativeRecording
            ))
        case .electrocardiogram(let session):
            guard let nativeRecording else {
                throw SensorKitRecordError.missingProviderValue("electrocardiogram.nativeRecording")
            }
            return .electrocardiogram(try SensorKitECGRecord(
                sourceRecordID: sourceRecordID,
                session: session,
                nativeRecording: nativeRecording
            ))
        }
    }

    /// Creates a record carrying Grove-generated native evidence at the requested location.
    public func sensorKitRecord(
        sourceRecordID: SensorKitSourceRecordID,
        title: String,
        location: SensorKitRecordingLocation,
        admission: SensorRawPayloadAdmission
    ) throws -> SensorKitRecord {
        guard let nativePayload else {
            throw SensorKitRecordError.invalidRecordingFormat
        }
        let nativeRecording = try SensorKitNativeRecording(
            title: title,
            format: .nativeRecording,
            payload: location.payload(bytes: nativePayload),
            admission: admission
        )
        return try sensorKitRecord(
            sourceRecordID: sourceRecordID,
            nativeRecording: nativeRecording
        )
    }

    private static func encodeJSON(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(value)
        try RegisteredRecordingFormat.nativeRecording.validatePayload(data)
        return data
    }
}


@available(iOS 18, *)
private struct DeviceUsageEvidence: Encodable {
    struct ApplicationUsage: Encodable {
        struct SupplementalCategory: Encodable {
            let identifier: String
        }
        struct TextInputSession: Encodable {
            let duration: TimeInterval
            let sessionTypeRawValue: Int
            let identifier: String
        }

        let bundleIdentifier: String?
        let reportApplicationIdentifier: String
        let relativeStartTime: TimeInterval
        let usageTime: TimeInterval
        let supplementalCategories: [SupplementalCategory]
        let textInputSessions: [TextInputSession]

        init(_ usage: SRDeviceUsageReport.SafeRepresentation.AppUsage) {
            bundleIdentifier = usage.bundleIdentifier
            reportApplicationIdentifier = usage.reportApplicationIdentifier
            relativeStartTime = usage.relativeStartTime
            usageTime = usage.usageTime
            supplementalCategories = usage.supplementalCategories
                .map { SupplementalCategory(identifier: $0.identifier) }
                .sorted { $0.identifier < $1.identifier }
            textInputSessions = usage.textInputSessions.map {
                TextInputSession(
                    duration: $0.duration,
                    sessionTypeRawValue: $0.sessionType.rawValue,
                    identifier: $0.identifier
                )
            }
        }
    }

    struct NotificationUsage: Encodable {
        let bundleIdentifier: String?
        let eventRawValue: Int
    }
    struct WebUsage: Encodable {
        let totalUsageTime: TimeInterval
    }

    let timestamp: Date
    let duration: TimeInterval
    let totalScreenWakes: Int
    let totalUnlocks: Int
    let totalUnlockDuration: TimeInterval
    let version: String
    let appUsageByCategory: [String: [ApplicationUsage]]
    let notificationUsageByCategory: [String: [NotificationUsage]]
    let webUsageByCategory: [String: [WebUsage]]

    init(_ report: SRDeviceUsageReport.SafeRepresentation) {
        timestamp = report.timestamp
        duration = report.duration
        totalScreenWakes = report.totalScreenWakes
        totalUnlocks = report.totalUnlocks
        totalUnlockDuration = report.totalUnlockDuration
        version = report.version
        appUsageByCategory = Dictionary(uniqueKeysWithValues: report.appUsageByCategory.map { category, usages in
            (category.rawValue, usages.map(ApplicationUsage.init))
        })
        notificationUsageByCategory = Dictionary(
            uniqueKeysWithValues: report.notificationUsageByCategory.map { category, usages in
                (category.rawValue, usages.map {
                    NotificationUsage(bundleIdentifier: $0.bundleIdentifier, eventRawValue: $0.event.rawValue)
                })
            }
        )
        webUsageByCategory = Dictionary(uniqueKeysWithValues: report.webUsageByCategory.map { category, usages in
            (category.rawValue, usages.map { WebUsage(totalUsageTime: $0.totalUsageTime) })
        })
    }
}


@available(iOS 17.4, *)
private struct ECGEvidence: Encodable {
    struct Batch: Encodable {
        struct Sample: Encodable {
            let flags: UInt
            let microvolts: Double
        }
        let offsetSeconds: TimeInterval
        let samples: [Sample]
    }

    let sessionIdentifier: String
    let sessionStates: [Int]
    let batches: [Batch]

    init(_ session: SensorKitECGSession) {
        sessionIdentifier = session.sessionIdentifier
        sessionStates = session.sessionStates.map(\.rawValue)
        batches = session.batches.map { batch in
            Batch(
                offsetSeconds: batch.offset,
                samples: batch.samples.map { sample in
                    Batch.Sample(
                        flags: sample.flags.rawValue,
                        microvolts: sample.voltage.converted(to: .microvolts).value
                    )
                }
            )
        }
    }
}
#endif
