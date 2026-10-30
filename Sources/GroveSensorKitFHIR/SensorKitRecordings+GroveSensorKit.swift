//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Public format-specific initializers read most clearly before the common record projection.
// swiftlint:disable type_contents_order

#if os(iOS)
public import CoreMotion
public import Foundation
public import GroveFHIRContract
public import GroveSensorKit
public import SensorKit


/// An already-fetched SensorKit row for which Grove publishes a registered tabular format.
public protocol SensorKitTabularSample: SensorKitSampleSafeRepresentation {
    static var groveSourceToken: String { get }
    static var groveRecordingFormat: RegisteredRecordingFormat { get }

    /// Every published row field, including the exact source-device product type when required.
    func groveRecordingFields(deviceProductType: String) -> [RecordingCSVWriter.Field]
}


/// A complete registry-conformant tabular payload prepared from already-fetched SensorKit values.
public struct SensorKitTabularRecording: Sendable {
    private enum StructuredProjection: Sendable {
        case accelerometer
        case wristTemperature(algorithmVersion: String)
        case none
    }

    public let sourceToken: String
    public let format: RegisteredRecordingFormat
    public let data: Data
    public let effectivePeriod: DateInterval
    public let retryEvidence: Data
    private let structuredProjection: StructuredProjection

    /// Encodes a homogeneous fetched batch through its Grove-owned row mapping.
    public init<Sample: SensorKitTabularSample>(
        samples: [Sample],
        deviceProductType: String
    ) throws {
        var writer = try Self.writer(for: Sample.groveRecordingFormat)
        for sample in samples {
            try writer.append(sample.groveRecordingFields(deviceProductType: deviceProductType))
        }
        try self.init(
            sourceToken: Sample.groveSourceToken,
            format: Sample.groveRecordingFormat,
            data: writer.data(),
            intervals: samples.map(\.timeRange),
            structuredProjection: Sample.groveRecordingFormat == .triaxialAccelerationSamples
                ? .accelerometer
                : .none
        )
    }

    @available(iOS 17, *)
    public init(wristTemperature session: SRWristTemperatureSession) throws {
        var writer = try Self.writer(for: .wristTemperatureSamples)
        let temperatures = Array(session.temperatures)
        for sample in temperatures {
            try writer.append([
                .timestamp(sample.timestamp),
                .number(sample.value.converted(to: .celsius).value),
                .number(sample.errorEstimate.converted(to: .celsius).value),
                .text(try Self.condition(sample.condition))
            ])
        }
        let data = writer.data()
        var evidence = Data()
        var versionLength = UInt64(session.version.utf8.count).bigEndian
        withUnsafeBytes(of: &versionLength) { evidence.append(contentsOf: $0) }
        evidence.append(contentsOf: session.version.utf8)
        evidence.append(data)
        try self.init(
            sourceToken: "SRSensor.wristTemperature",
            format: .wristTemperatureSamples,
            data: data,
            intervals: temperatures.map { $0.timestamp..<$0.timestamp },
            retryEvidence: evidence,
            structuredProjection: .wristTemperature(algorithmVersion: session.version)
        )
    }

    /// Builds the structured projection declared by the catalog, or its raw recording document.
    public func sensorKitRecord(
        sourceRecordID: SensorKitSourceRecordID,
        title: String,
        location: SensorKitRecordingLocation,
        admission: SensorRawPayloadAdmission
    ) throws -> SensorKitRecord {
        let nativeRecording = try SensorKitNativeRecording(
            title: title,
            format: format,
            payload: location.payload(bytes: data),
            admission: admission
        )
        switch structuredProjection {
        case .accelerometer:
            return .accelerometer(try SensorKitAccelerometerRecord(
                sourceRecordID: sourceRecordID,
                nativeRecording: nativeRecording
            ))
        case .wristTemperature(let algorithmVersion):
            return .wristTemperature(try SensorKitWristTemperatureRecord(
                sourceRecordID: sourceRecordID,
                algorithmVersion: algorithmVersion,
                nativeRecording: nativeRecording
            ))
        case .none:
            return .raw(try SensorKitRawRecord(
                sourceRecordID: sourceRecordID,
                sourceToken: sourceToken,
                effectivePeriod: effectivePeriod,
                nativeRecording: nativeRecording
            ))
        }
    }

    private init(
        sourceToken: String,
        format: RegisteredRecordingFormat,
        data: Data,
        intervals: [Range<Date>],
        retryEvidence: Data? = nil,
        structuredProjection: StructuredProjection = .none
    ) throws {
        guard let start = intervals.lazy.map(\.lowerBound).min(),
              let end = intervals.lazy.map(\.upperBound).max() else {
            throw SensorKitRecordError.emptySamples
        }
        try format.validatePayload(data)
        self.sourceToken = sourceToken
        self.format = format
        self.data = data
        self.effectivePeriod = DateInterval(start: start, end: end)
        self.retryEvidence = retryEvidence ?? data
        self.structuredProjection = structuredProjection
    }

    private static func writer(for format: RegisteredRecordingFormat) throws -> RecordingCSVWriter {
        guard let columns = format.csvColumns else {
            throw SensorKitRecordError.invalidRecordingFormat
        }
        return RecordingCSVWriter(columns: columns)
    }

    @available(iOS 17, *)
    private static func condition(_ condition: SRWristTemperature.Condition) throws -> String {
        let known = SRWristTemperature.Condition.offWrist.rawValue
            | SRWristTemperature.Condition.onCharger.rawValue
            | SRWristTemperature.Condition.inMotion.rawValue
        guard condition.rawValue & ~known == 0 else {
            throw SensorKitRecordError.unsupportedProviderValue(
                field: "wristTemperature.condition",
                rawValue: Int(condition.rawValue & ~known)
            )
        }
        var values: [String] = []
        if condition.contains(.offWrist) { values.append("offWrist") }
        if condition.contains(.onCharger) { values.append("onCharger") }
        if condition.contains(.inMotion) { values.append("inMotion") }
        return values.joined(separator: ",")
    }
}


extension CMRecordedAccelerometerData.SafeRepresentation: SensorKitTabularSample {
    public static var groveSourceToken: String { "SRSensor.accelerometer" }
    public static var groveRecordingFormat: RegisteredRecordingFormat { .triaxialAccelerationSamples }

    public func groveRecordingFields(deviceProductType: String) -> [RecordingCSVWriter.Field] {
        [
            .timestamp(timestamp),
            .text(String(identifier)),
            .number(acceleration.x),
            .number(acceleration.y),
            .number(acceleration.z),
            .text(deviceProductType)
        ]
    }
}


@available(iOS 18, *)
extension CMHighFrequencyHeartRateData.SafeRepresentation: SensorKitTabularSample {
    public static var groveSourceToken: String { "SRSensor.heartRate" }
    public static var groveRecordingFormat: RegisteredRecordingFormat { .heartRateSamples }

    public func groveRecordingFields(deviceProductType: String) -> [RecordingCSVWriter.Field] {
        [.timestamp(timestamp), .number(value), .integer(confidence.rawValue), .text(deviceProductType)]
    }
}


extension SRAmbientLightSample.SafeRepresentation: SensorKitTabularSample {
    public static var groveSourceToken: String { "SRSensor.ambientLightSensor" }
    public static var groveRecordingFormat: RegisteredRecordingFormat { .ambientLightSamples }

    public func groveRecordingFields(deviceProductType: String) -> [RecordingCSVWriter.Field] {
        [
            .timestamp(timestamp),
            .number(lux.converted(to: .lux).value),
            .text(placement.description),
            .number(Double(chromacity.x)),
            .number(Double(chromacity.y)),
            .text(deviceProductType)
        ]
    }
}


extension CMRecordedPressureData.SafeRepresentation: SensorKitTabularSample {
    public static var groveSourceToken: String { "SRSensor.ambientPressure" }
    public static var groveRecordingFormat: RegisteredRecordingFormat { .ambientPressureSamples }

    public func groveRecordingFields(deviceProductType: String) -> [RecordingCSVWriter.Field] {
        [
            .timestamp(timestamp),
            .text(String(identifier)),
            .number(pressure.converted(to: .kilopascals).value),
            .number(temperature.converted(to: .celsius).value),
            .text(deviceProductType)
        ]
    }
}


extension CMPedometerData.SafeRepresentation: SensorKitTabularSample {
    public static var groveSourceToken: String { "SRSensor.pedometerData" }
    public static var groveRecordingFormat: RegisteredRecordingFormat { .pedometerSamples }

    public func groveRecordingFields(deviceProductType: String) -> [RecordingCSVWriter.Field] {
        [
            .timestamp(timeRange.lowerBound),
            .timestamp(timeRange.upperBound),
            .integer(numberOfSteps),
            distance.map(RecordingCSVWriter.Field.number) ?? .absent,
            floorsAscended.map(RecordingCSVWriter.Field.integer) ?? .absent,
            floorsDescended.map(RecordingCSVWriter.Field.integer) ?? .absent,
            currentPace.map(RecordingCSVWriter.Field.number) ?? .absent,
            currentCadence.map(RecordingCSVWriter.Field.number) ?? .absent,
            averageActivePace.map(RecordingCSVWriter.Field.number) ?? .absent,
            .text(deviceProductType)
        ]
    }
}
#endif
