//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The nested wire types follow the published grammar and use its x/y/z field names.
// swiftlint:disable file_types_order type_contents_order identifier_name

public import Foundation


/// One complete `photoplethysmogram-samples` payload.
///
/// This type owns the registry's binary grammar. Encoding always produces canonical bytes and
/// decoding rejects malformed, non-canonical, or trailing data.
public struct SensorKitPPGRecording: Equatable, Sendable {
    public let records: [Record]

    public init(records: [Record]) {
        self.records = records
    }

    public init(data: Data) throws {
        var reader = RecordingBinaryReader(data)
        records = try reader.readArray { reader in
            try Record(from: &reader)
        }
        try reader.finish()
    }

    public func encoded() throws -> Data {
        var writer = RecordingBinaryWriter()
        try writer.writeArray(records) { writer, record in
            try record.encode(to: &writer)
        }
        return writer.data()
    }

    /// Encodes this recording once for upload, retry identity, and FHIR record construction.
    public func prepared() throws -> SensorKitPreparedPPGRecording {
        try SensorKitPreparedPPGRecording(data: encoded())
    }

    /// Timing and counts derived from the exact records represented by the payload.
    public var summary: Summary? {
        var instants: [Date] = []
        instants.reserveCapacity(
            records.count
                + records.lazy.map(\.opticalSamples.count).reduce(0, +)
                + records.lazy.map(\.accelerometerSamples.count).reduce(0, +)
        )
        for record in records {
            instants.append(record.instant)
            instants.append(contentsOf: record.opticalSamples.map {
                record.startDate.addingTimeInterval(Double($0.nanosecondsSinceStart) / 1_000_000_000)
            })
            instants.append(contentsOf: record.accelerometerSamples.map {
                record.startDate.addingTimeInterval(Double($0.nanosecondsSinceStart) / 1_000_000_000)
            })
        }
        guard let start = instants.min(), let end = instants.max(),
              start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite else {
            return nil
        }
        return Summary(
            coverage: DateInterval(start: start, end: end),
            recordCount: records.count,
            opticalSampleCount: records.lazy.map(\.opticalSamples.count).reduce(0, +),
            accelerometerSampleCount: records.lazy.map(\.accelerometerSamples.count).reduce(0, +)
        )
    }

    public struct Summary: Equatable, Sendable {
        public let coverage: DateInterval
        public let recordCount: Int
        public let opticalSampleCount: Int
        public let accelerometerSampleCount: Int
    }

    public struct Record: Equatable, Sendable {
        public let startDate: Date
        public let nanosecondsSinceStart: Int64
        public let temperature: Double?
        public let usage: [String]
        public let opticalSamples: [OpticalSample]
        public let accelerometerSamples: [AccelerometerSample]

        public init(
            startDate: Date,
            nanosecondsSinceStart: Int64,
            temperature: Double?,
            usage: [String],
            opticalSamples: [OpticalSample],
            accelerometerSamples: [AccelerometerSample]
        ) {
            self.startDate = startDate
            self.nanosecondsSinceStart = nanosecondsSinceStart
            self.temperature = temperature
            self.usage = usage
            self.opticalSamples = opticalSamples
            self.accelerometerSamples = accelerometerSamples
        }

        var instant: Date {
            startDate.addingTimeInterval(Double(nanosecondsSinceStart) / 1_000_000_000)
        }

        fileprivate init(from reader: inout RecordingBinaryReader) throws {
            startDate = Date(timeIntervalSince1970: try reader.readFloat64())
            nanosecondsSinceStart = try reader.readSignedVarint()
            temperature = try reader.readOptionalFloat64()
            usage = try reader.readArray { try $0.readString() }
            opticalSamples = try reader.readArray { try OpticalSample(from: &$0) }
            accelerometerSamples = try reader.readArray { try AccelerometerSample(from: &$0) }
        }

        fileprivate func encode(to writer: inout RecordingBinaryWriter) throws {
            try writer.writeFloat64(startDate.timeIntervalSince1970)
            writer.writeVarint(nanosecondsSinceStart)
            try writer.writeOptionalFloat64(temperature)
            writer.writeArray(usage) { $0.writeString($1) }
            try writer.writeArray(opticalSamples) { try $1.encode(to: &$0) }
            try writer.writeArray(accelerometerSamples) { try $1.encode(to: &$0) }
        }
    }

    public struct OpticalSample: Equatable, Sendable {
        public let emitter: Int64
        public let activePhotodiodeIndexes: [UInt64]
        public let signalIdentifier: Int64
        public let nominalWavelength: Double
        public let effectiveWavelength: Double
        public let samplingFrequency: Double
        public let nanosecondsSinceStart: Int64
        public let conditions: [String]
        public let noiseTerms: NoiseTerms?
        public let normalizedReflectance: Double?

        public init(
            emitter: Int64,
            activePhotodiodeIndexes: [UInt64],
            signalIdentifier: Int64,
            nominalWavelength: Double,
            effectiveWavelength: Double,
            samplingFrequency: Double,
            nanosecondsSinceStart: Int64,
            conditions: [String],
            noiseTerms: NoiseTerms?,
            normalizedReflectance: Double?
        ) {
            self.emitter = emitter
            self.activePhotodiodeIndexes = activePhotodiodeIndexes
            self.signalIdentifier = signalIdentifier
            self.nominalWavelength = nominalWavelength
            self.effectiveWavelength = effectiveWavelength
            self.samplingFrequency = samplingFrequency
            self.nanosecondsSinceStart = nanosecondsSinceStart
            self.conditions = conditions
            self.noiseTerms = noiseTerms
            self.normalizedReflectance = normalizedReflectance
        }

        fileprivate init(from reader: inout RecordingBinaryReader) throws {
            emitter = try reader.readSignedVarint()
            activePhotodiodeIndexes = try reader.readCanonicalSet { try $0.readVarint() }
            signalIdentifier = try reader.readSignedVarint()
            nominalWavelength = try reader.readFloat64()
            effectiveWavelength = try reader.readFloat64()
            samplingFrequency = try reader.readFloat64()
            nanosecondsSinceStart = try reader.readSignedVarint()
            conditions = try reader.readArray { try $0.readString() }
            noiseTerms = try reader.readBoolean() ? try NoiseTerms(from: &reader) : nil
            normalizedReflectance = try reader.readOptionalFloat64()
        }

        fileprivate func encode(to writer: inout RecordingBinaryWriter) throws {
            writer.writeVarint(emitter)
            try writer.writeCanonicalSet(activePhotodiodeIndexes) { $0.writeVarint($1) }
            writer.writeVarint(signalIdentifier)
            try writer.writeFloat64(nominalWavelength)
            try writer.writeFloat64(effectiveWavelength)
            try writer.writeFloat64(samplingFrequency)
            writer.writeVarint(nanosecondsSinceStart)
            writer.writeArray(conditions) { $0.writeString($1) }
            writer.writeBoolean(noiseTerms != nil)
            if let noiseTerms {
                try noiseTerms.encode(to: &writer)
            }
            try writer.writeOptionalFloat64(normalizedReflectance)
        }
    }

    public struct NoiseTerms: Equatable, Sendable {
        public let whiteNoise: Double
        public let pinkNoise: Double
        public let backgroundNoise: Double
        public let backgroundNoiseOffset: Double

        public init(
            whiteNoise: Double,
            pinkNoise: Double,
            backgroundNoise: Double,
            backgroundNoiseOffset: Double
        ) {
            self.whiteNoise = whiteNoise
            self.pinkNoise = pinkNoise
            self.backgroundNoise = backgroundNoise
            self.backgroundNoiseOffset = backgroundNoiseOffset
        }

        fileprivate init(from reader: inout RecordingBinaryReader) throws {
            whiteNoise = try reader.readFloat64()
            pinkNoise = try reader.readFloat64()
            backgroundNoise = try reader.readFloat64()
            backgroundNoiseOffset = try reader.readFloat64()
        }

        fileprivate func encode(to writer: inout RecordingBinaryWriter) throws {
            try writer.writeFloat64(whiteNoise)
            try writer.writeFloat64(pinkNoise)
            try writer.writeFloat64(backgroundNoise)
            try writer.writeFloat64(backgroundNoiseOffset)
        }
    }

    public struct AccelerometerSample: Equatable, Sendable {
        public let nanosecondsSinceStart: Int64
        public let samplingFrequency: Double
        public let x: Double
        public let y: Double
        public let z: Double

        public init(
            nanosecondsSinceStart: Int64,
            samplingFrequency: Double,
            x: Double,
            y: Double,
            z: Double
        ) {
            self.nanosecondsSinceStart = nanosecondsSinceStart
            self.samplingFrequency = samplingFrequency
            self.x = x
            self.y = y
            self.z = z
        }

        fileprivate init(from reader: inout RecordingBinaryReader) throws {
            nanosecondsSinceStart = try reader.readSignedVarint()
            samplingFrequency = try reader.readFloat64()
            x = try reader.readFloat64()
            y = try reader.readFloat64()
            z = try reader.readFloat64()
        }

        fileprivate func encode(to writer: inout RecordingBinaryWriter) throws {
            writer.writeVarint(nanosecondsSinceStart)
            try writer.writeFloat64(samplingFrequency)
            try writer.writeFloat64(x)
            try writer.writeFloat64(y)
            try writer.writeFloat64(z)
        }
    }
}


/// One canonical PPG byte buffer shared by persistence and FHIR record construction.
///
/// Keeping this value prevents large PPG batches from being encoded again after the caller has
/// already persisted their exact bytes. The initializer stays internal so bytes exposed here can
/// only originate from Grove's canonical encoder.
public struct SensorKitPreparedPPGRecording: Sendable {
    public let data: Data

    public var format: RegisteredRecordingFormat { .photoplethysmogramSamples }

    /// Exact evidence for matching a retried source record to these canonical bytes.
    public var retryEvidence: Data { data }

    init(data: Data) {
        self.data = data
    }

    /// Builds the FHIR input from the same canonical bytes exposed in ``data``.
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
        return .ppg(try SensorKitPPGRecord(
            sourceRecordID: sourceRecordID,
            nativeRecording: nativeRecording
        ))
    }
}
