//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveSensorKitFHIR
import Testing


@Suite
struct SensorKitPPGLegacyDecodingTests {
    /// Writes the legacy encoding as My Heart Counts' `BinaryEncoder` did: varints without ZigZag, binary64
    /// little-endian, strings as a byte count then one varint per byte, sets in the order given.
    private struct LegacyWriter {
        var bytes: [UInt8] = []

        mutating func varint(_ value: UInt64) {
            var remaining = value
            while remaining > 0x7F {
                bytes.append(UInt8(remaining & 0x7F) | 0x80)
                remaining >>= 7
            }
            bytes.append(UInt8(remaining))
        }

        mutating func varint(_ value: Int64) {
            varint(UInt64(bitPattern: value))
        }

        mutating func float64(_ value: Double) {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { bytes.append(contentsOf: $0) }
        }

        mutating func optionalFloat64(_ value: Double?) {
            bytes.append(value == nil ? 0 : 1)
            if let value {
                float64(value)
            }
        }

        mutating func string(_ value: String) {
            varint(UInt64(value.utf8.count))
            for byte in value.utf8 {
                varint(UInt64(byte))
            }
        }
    }

    private static var expected: SensorKitPPGRecording.Record {
        SensorKitPPGRecording.Record(
            startDate: Date(timeIntervalSince1970: 1_776_517_050.25),
            nanosecondsSinceStart: 1_500_000_000,
            temperature: 31.5,
            usage: ["ForegroundHeartRate", "Größe"],
            opticalSamples: [
                SensorKitPPGRecording.OpticalSample(
                    emitter: 2,
                    activePhotodiodeIndexes: [1, 3],
                    signalIdentifier: 7,
                    nominalWavelength: 525,
                    effectiveWavelength: 524.5,
                    samplingFrequency: 256,
                    nanosecondsSinceStart: 3_906_250,
                    conditions: ["SignalSaturation"],
                    noiseTerms: .init(whiteNoise: 0.1, pinkNoise: 0.2, backgroundNoise: 0.3, backgroundNoiseOffset: 0.4),
                    normalizedReflectance: 0.75
                ),
                SensorKitPPGRecording.OpticalSample(
                    emitter: 1,
                    activePhotodiodeIndexes: [0],
                    signalIdentifier: -1,
                    nominalWavelength: 850,
                    effectiveWavelength: 849.25,
                    samplingFrequency: 256,
                    nanosecondsSinceStart: -5,
                    conditions: [],
                    noiseTerms: nil,
                    normalizedReflectance: nil
                )
            ],
            accelerometerSamples: [
                SensorKitPPGRecording.AccelerometerSample(nanosecondsSinceStart: 7_812_500, samplingFrequency: 64, x: -0.0, y: 0.98, z: -0.125)
            ]
        )
    }

    /// One sample with two optical and one accelerometer sample, covering what the registered encoding writes
    /// differently: an unordered photodiode set, a non-ASCII string, a negative zero and absent optionals.
    private static func legacySample(writer: inout LegacyWriter) {
        writer.float64(1_776_517_050.25)
        writer.varint(Int64(1_500_000_000))
        writer.optionalFloat64(31.5)
        writer.varint(UInt64(2))
        writer.string("ForegroundHeartRate")
        writer.string("Größe")
        writer.varint(UInt64(2))
        // Optical sample 1: photodiodes {3, 1}, written in hash order.
        writer.varint(Int64(2))
        writer.varint(UInt64(2))
        writer.varint(UInt64(3))
        writer.varint(UInt64(1))
        writer.varint(Int64(7))
        writer.float64(525)
        writer.float64(524.5)
        writer.float64(256)
        writer.varint(Int64(3_906_250))
        writer.varint(UInt64(1))
        writer.string("SignalSaturation")
        writer.bytes.append(1)
        writer.float64(0.1)
        writer.float64(0.2)
        writer.float64(0.3)
        writer.float64(0.4)
        writer.optionalFloat64(0.75)
        // Optical sample 2: one photodiode, no conditions, no noise terms, no reflectance.
        writer.varint(Int64(1))
        writer.varint(UInt64(1))
        writer.varint(UInt64(0))
        writer.varint(Int64(-1))
        writer.float64(850)
        writer.float64(849.25)
        writer.float64(256)
        writer.varint(Int64(-5))
        writer.varint(UInt64(0))
        writer.bytes.append(0)
        writer.optionalFloat64(nil)
        // Accelerometer sample with a negative zero.
        writer.varint(UInt64(1))
        writer.varint(Int64(7_812_500))
        writer.float64(64)
        writer.float64(-0.0)
        writer.float64(0.98)
        writer.float64(-0.125)
    }

    @Test("A legacy .mhcPPG payload decodes to the same records the registered encoding carries")
    func legacyPayloadDecodes() throws {
        var writer = LegacyWriter()
        writer.varint(UInt64(2))
        Self.legacySample(writer: &writer)
        Self.legacySample(writer: &writer)
        let recording = try SensorKitPPGRecording(legacyMyHeartCountsData: Data(writer.bytes))
        #expect(recording.records == [Self.expected, Self.expected])
        let negativeZero = try #require(recording.records.first?.accelerometerSamples.first?.x)
        #expect(negativeZero.sign == .minus)
    }

    @Test("The legacy decoder ignores bytes after the last sample and fails on a truncated one, as the legacy decoder did")
    func legacyPayloadBoundaries() throws {
        var writer = LegacyWriter()
        writer.varint(UInt64(1))
        Self.legacySample(writer: &writer)
        let complete = writer.bytes
        #expect(try SensorKitPPGRecording(legacyMyHeartCountsData: Data(complete + [0xFF, 0x00])).records == [Self.expected])
        #expect(throws: SensorKitPPGRecording.LegacyDecodingError.unexpectedEnd) {
            try SensorKitPPGRecording(legacyMyHeartCountsData: Data(complete.dropLast()))
        }
    }

    @Test("The registered decoder does not read legacy bytes as the same records, so the file's extension must choose")
    func registeredDecoderDoesNotReadLegacyBytes() {
        var writer = LegacyWriter()
        writer.varint(UInt64(1))
        Self.legacySample(writer: &writer)
        let registered = try? SensorKitPPGRecording(data: Data(writer.bytes))
        #expect(registered?.records != [Self.expected])
    }
}
