//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// The primitives of the legacy encoding, as My Heart Counts' `BinaryEncoder` wrote them.
private struct LegacyReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ data: Data) {
        bytes = Array(data)
    }

    mutating func byte() throws(SensorKitPPGRecording.LegacyDecodingError) -> UInt8 {
        guard offset < bytes.count else {
            throw .unexpectedEnd
        }
        defer {
            offset += 1
        }
        return bytes[offset]
    }

    /// Unsigned LEB128 of at most ten bytes; bits past the 64th are dropped, as the legacy decoder dropped them.
    mutating func varint() throws(SensorKitPPGRecording.LegacyDecodingError) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<10 {
            let byte = try byte()
            value |= UInt64(byte & 0x7F) << UInt64(index * 7)
            if byte & 0x80 == 0 {
                return value
            }
        }
        throw .varintOverflow
    }

    mutating func signedVarint() throws(SensorKitPPGRecording.LegacyDecodingError) -> Int64 {
        Int64(bitPattern: try varint())
    }

    /// A binary64 whose bytes are little-endian: the legacy encoder byte-swapped the bit pattern, then wrote it
    /// big-endian.
    mutating func float64() throws(SensorKitPPGRecording.LegacyDecodingError) -> Double {
        guard bytes.count - offset >= 8 else {
            offset = bytes.count
            throw .unexpectedEnd
        }
        var pattern: UInt64 = 0
        for byte in bytes[offset..<(offset + 8)].reversed() {
            pattern = (pattern << 8) | UInt64(byte)
        }
        offset += 8
        return Double(bitPattern: pattern)
    }

    mutating func boolean() throws(SensorKitPPGRecording.LegacyDecodingError) -> Bool {
        switch try byte() {
        case 0x00: false
        case 0x01: true
        case let byte: throw .invalidBoolean(byte)
        }
    }

    mutating func optionalFloat64() throws(SensorKitPPGRecording.LegacyDecodingError) -> Double? {
        try boolean() ? try float64() : nil
    }

    /// A byte count, then each UTF-8 byte as a varint truncated to eight bits.
    mutating func string() throws(SensorKitPPGRecording.LegacyDecodingError) -> String {
        let count = try varint()
        var utf8: [UInt8] = []
        utf8.reserveCapacity(Int(min(count, UInt64(bytes.count - offset))))
        for _ in 0..<count {
            utf8.append(UInt8(truncatingIfNeeded: try varint()))
        }
        guard let value = String(bytes: utf8, encoding: .utf8) else {
            throw .invalidUTF8
        }
        return value
    }

    /// A varint element count, then each element in order.
    mutating func array<Element>(
        _ element: (inout Self) throws(SensorKitPPGRecording.LegacyDecodingError) -> Element
    ) throws(SensorKitPPGRecording.LegacyDecodingError) -> [Element] {
        let count = try varint()
        var values: [Element] = []
        values.reserveCapacity(Int(min(count, UInt64(bytes.count - offset))))
        for _ in 0..<count {
            values.append(try element(&self))
        }
        return values
    }
}


extension SensorKitPPGRecording {
    /// Why bytes could not be read in My Heart Counts' legacy PPG encoding.
    public enum LegacyDecodingError: Error, Equatable, Sendable {
        /// The bytes ended before the value did.
        case unexpectedEnd
        /// A varint ran past the ten bytes a 64-bit value can occupy.
        case varintOverflow
        /// A boolean byte was neither `0x00` nor `0x01`.
        case invalidBoolean(UInt8)
        /// A string's bytes are not valid UTF-8.
        case invalidUTF8
    }

    /// Reads a recording in the encoding My Heart Counts wrote before this registered format (its `.mhcPPG` files),
    /// accepting exactly what that app's decoder accepted.
    ///
    /// The two encodings share their field order and carry no version, so the bytes alone cannot tell them apart;
    /// pick this decoder by the file's extension. The legacy encoding differs from ``init(data:)``'s in that:
    /// - every binary64 is little-endian;
    /// - a string is its UTF-8 byte count, then each byte as its own varint;
    /// - a photodiode set is in no particular order; it is read here in ascending order, without duplicates;
    /// - values are kept as written: no finiteness or zero-sign check, no shortest-varint check, and bytes after the
    ///   last sample are ignored.
    public init(legacyMyHeartCountsData data: Data) throws(LegacyDecodingError) {
        var reader = LegacyReader(data)
        records = try reader.array { reader throws(LegacyDecodingError) in
            try Record(legacyFrom: &reader)
        }
    }
}


extension SensorKitPPGRecording.Record {
    fileprivate init(legacyFrom reader: inout LegacyReader) throws(SensorKitPPGRecording.LegacyDecodingError) {
        self.init(
            startDate: Date(timeIntervalSince1970: try reader.float64()),
            nanosecondsSinceStart: try reader.signedVarint(),
            temperature: try reader.optionalFloat64(),
            usage: try reader.array { reader throws(SensorKitPPGRecording.LegacyDecodingError) in try reader.string() },
            opticalSamples: try reader.array { reader throws(SensorKitPPGRecording.LegacyDecodingError) in
                try SensorKitPPGRecording.OpticalSample(legacyFrom: &reader)
            },
            accelerometerSamples: try reader.array { reader throws(SensorKitPPGRecording.LegacyDecodingError) in
                SensorKitPPGRecording.AccelerometerSample(
                    nanosecondsSinceStart: try reader.signedVarint(),
                    samplingFrequency: try reader.float64(),
                    x: try reader.float64(),
                    y: try reader.float64(),
                    z: try reader.float64()
                )
            }
        )
    }
}


extension SensorKitPPGRecording.OpticalSample {
    fileprivate init(legacyFrom reader: inout LegacyReader) throws(SensorKitPPGRecording.LegacyDecodingError) {
        let emitter = try reader.signedVarint()
        // The legacy encoder wrote a Swift `Set`, so its order is meaningless and it held no duplicates.
        let photodiodes = Set(try reader.array { reader throws(SensorKitPPGRecording.LegacyDecodingError) in try reader.varint() })
        self.init(
            emitter: emitter,
            activePhotodiodeIndexes: photodiodes.sorted(),
            signalIdentifier: try reader.signedVarint(),
            nominalWavelength: try reader.float64(),
            effectiveWavelength: try reader.float64(),
            samplingFrequency: try reader.float64(),
            nanosecondsSinceStart: try reader.signedVarint(),
            conditions: try reader.array { reader throws(SensorKitPPGRecording.LegacyDecodingError) in try reader.string() },
            noiseTerms: try reader.boolean()
                ? SensorKitPPGRecording.NoiseTerms(
                    whiteNoise: try reader.float64(),
                    pinkNoise: try reader.float64(),
                    backgroundNoise: try reader.float64(),
                    backgroundNoiseOffset: try reader.float64()
                )
                : nil,
            normalizedReflectance: try reader.optionalFloat64()
        )
    }
}
