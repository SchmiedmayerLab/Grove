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

    /// What My Heart Counts' own `BinaryEncoder` wrote for the three samples its `PPGBinaryCodingTests` encoded, kept
    /// here when that encoder was removed: the bytes the shipped app produced.
    private static let myHeartCountsEncoded = Data(
        base64Encoded: """
        A+sz7OmxVdpB+evX9qmIsgIBAAAAAAA6QEABE0ZvcmVncm91bmRIZWFydFJhdGUCCgICAQAAAAAAAGiAQAAAAAAAaIBAAAAAAAAA
        YECa4df2qYiyAgABAAAAgLK9Hj0AAABAhHhgPQAAAIC7466+AAAAINo7TD0BAAAAAJ8GpD8MAgMAAAAAAAAAaIBAAAAAAABogEAA
        AAAAAABgQK/o1/apiLICARBTaWduYWxTYXR1cmF0aW9uAQAAAECdYiM9AAAAgDqmaz0AAABgii7EPgAAAMBW/ks9AQAAAKBF8qk/
        Afnr1/apiLICAAAAAAAAYEAAAAAAoCrvPwAAAACAHcE/AAAAAACqv7/rM+zpsVXaQfXM88Ls2rECAQAAAAAADUFAARBCYWNrZ3Jv
        dW5kU3lzdGVtAgEBAAEAAAAAAJCKQAAAAABwo4pAAAAAAAAAIEDgxfPC7NqxAgABAAAAQEEouz0AAADg+b+mPQAAAGB8vui+AAAA
        oA9W0D0BAAAAIBmJxz8BAQMBAAAAAACQikAAAAAAcKOKQAAAAAAAACBA4MXzwuzasQIAAQAAAEChLrs9AAAAQB/OsD0AAABA2K/h
        PgAAAEACGc49AQAAAGBdm8w/CN3w347s2rECAAAAAAAAUEAAAAAAADzfvwAAAACAU+c/AAAAAID+3j+Fx5mW7NqxAgAAAAAAAFBA
        AAAAAMBA378AAAAAgDfnPwAAAACAwN4/rZ3TnezasQIAAAAAAABQQAAAAACAPt+/AAAAAMBF5z8AAAAAANXeP9XzjKXs2rECAAAA
        AAAAUEAAAAAAAETfvwAAAABgXuc/AAAAAMD23j/9ycas7NqxAgAAAAAAAFBAAAAAAABQ378AAAAAIH7nPwAAAACAIN8/paCAtOza
        sQIAAAAAAABQQAAAAAAAI9+/AAAAAABi5z8AAAAAwAjfP832ubvs2rECAAAAAAAAUEAAAAAAALvevwAAAACAPuc/AAAAAECn3j/1
        zPPC7NqxAgAAAAAAAFBAAAAAAID43r8AAAAAQDXnPwAAAACAk94/6zPs6bFV2kHuupS374iyAgEAAAAAAKhAQAITRm9yZWdyb3Vu
        ZEhlYXJ0UmF0ZRBCYWNrZ3JvdW5kU3lzdGVtAgoCAgEAAAAAAABogEAAAAAAAGiAQAAAAAAAAGBAsKWUt++IsgIBEFNpZ25hbFNh
        dHVyYXRpb24BAAAA4NyjIj0AAABgFUJpPQAAAMAaduK+AAAAoA07TD0BAAAAgI7MqD8MAgMAAAAAAAAAaIBAAAAAAABogEAAAAAA
        AABgQMWslLfviLICARBTaWduYWxTYXR1cmF0aW9uAQAAAECAmSI9AAAAoANOaT0AAACgSo3dvgAAAEB+/Us9AQAAAEBp0qg/CNbe
        gIPviLICAAAAAAAAUEAAAAAAAMTRPwAAAACAIOo/AAAAAMB00r/+tLqK74iyAgAAAAAAAFBAAAAAAEDj2D8AAAAAoK7xPwAAAAAA
        vte/pov0ke+IsgIAAAAAAABQQAAAAACAh9M/AAAAAICC8T8AAAAAgAHTv87hrZnviLICAAAAAAAAUEAAAAAAgGzAPwAAAADgrus/
        AAAAAADpw7/2t+eg74iyAgAAAAAAAFBAAAAAAACwlr8AAAAAwCPsPwAAAAAAdbu/no6hqO+IsgIAAAAAAABQQAAAAAAAyra/AAAA
        AFCc8D8AAAAAAPzOv8bk2q/viLICAAAAAAAAUEAAAAAAAISwvwAAAAAwYfA/AAAAAADq1r/uupS374iyAgAAAAAAAFBAAAAAAABg
        Yj8AAAAAILrtPwAAAADALde/
        """,
        options: .ignoreUnknownCharacters
    )

    /// The samples `myHeartCountsEncoded` holds, as My Heart Counts' own decoder read them back.
    private static let myHeartCountsSamples: [SensorKitPPGRecording.Record] = [
        SensorKitPPGRecording.Record(
            startDate: Date(timeIntervalSince1970: 1767294887.6906688),
            nanosecondsSinceStart: 1346088365061625,
            temperature: 32.453125,
            usage: ["ForegroundHeartRate"],
            opticalSamples: [
                SensorKitPPGRecording.OpticalSample(
                    emitter: 10,
                    activePhotodiodeIndexes: [1, 2],
                    signalIdentifier: 0,
                    nominalWavelength: 525.0,
                    effectiveWavelength: 525.0,
                    samplingFrequency: 128.0,
                    nanosecondsSinceStart: 1346088365060250,
                    conditions: [],
                    noiseTerms: .init(
                        whiteNoise: 2.7303497191020348e-14,
                        pinkNoise: 4.681273814768905e-13,
                        backgroundNoise: -9.205812148138648e-07,
                        backgroundNoiseOffset: 2.006131941340375e-13
                    ),
                    normalizedReflectance: 0.039113014936447144
                ),
                SensorKitPPGRecording.OpticalSample(
                    emitter: 12,
                    activePhotodiodeIndexes: [0, 3],
                    signalIdentifier: 0,
                    nominalWavelength: 525.0,
                    effectiveWavelength: 525.0,
                    samplingFrequency: 128.0,
                    nanosecondsSinceStart: 1346088365061167,
                    conditions: ["SignalSaturation"],
                    noiseTerms: .init(
                        whiteNoise: 3.443505382097825e-14,
                        pinkNoise: 7.85841227160522e-13,
                        backgroundNoise: 2.4058579128904967e-06,
                        backgroundNoiseOffset: 1.989058603154431e-13
                    ),
                    normalizedReflectance: 0.05067651346325874
                )
            ],
            accelerometerSamples: [
                SensorKitPPGRecording.AccelerometerSample(
                    nanosecondsSinceStart: 1346088365061625,
                    samplingFrequency: 128.0,
                    x: 0.9739532470703125,
                    y: 0.1337127685546875,
                    z: -0.123687744140625
                )
            ]
        ),
        SensorKitPPGRecording.Record(
            startDate: Date(timeIntervalSince1970: 1767294887.6906688),
            nanosecondsSinceStart: 1344525693675125,
            temperature: 34.1015625,
            usage: ["BackgroundSystem"],
            opticalSamples: [
                SensorKitPPGRecording.OpticalSample(
                    emitter: 1,
                    activePhotodiodeIndexes: [0],
                    signalIdentifier: 1,
                    nominalWavelength: 850.0,
                    effectiveWavelength: 852.4296875,
                    samplingFrequency: 8.0,
                    nanosecondsSinceStart: 1344525693674208,
                    conditions: [],
                    noiseTerms: .init(
                        whiteNoise: 2.4699371020675542e-11,
                        pinkNoise: 1.0345459731941897e-11,
                        backgroundNoise: -1.1798899322457146e-05,
                        backgroundNoiseOffset: 5.943066178071277e-11
                    ),
                    normalizedReflectance: 0.18387140333652496
                ),
                SensorKitPPGRecording.OpticalSample(
                    emitter: 1,
                    activePhotodiodeIndexes: [3],
                    signalIdentifier: 1,
                    nominalWavelength: 850.0,
                    effectiveWavelength: 852.4296875,
                    samplingFrequency: 8.0,
                    nanosecondsSinceStart: 1344525693674208,
                    conditions: [],
                    noiseTerms: .init(
                        whiteNoise: 2.4722019570377896e-11,
                        pinkNoise: 1.528420792706875e-11,
                        backgroundNoise: 8.43376801640261e-06,
                        backgroundNoiseOffset: 5.4747380240360854e-11
                    ),
                    normalizedReflectance: 0.2234913557767868
                )
            ],
            accelerometerSamples: [
                SensorKitPPGRecording.AccelerometerSample(
                    nanosecondsSinceStart: 1344525584300125,
                    samplingFrequency: 64.0,
                    x: -0.488037109375,
                    y: 0.72894287109375,
                    z: 0.484283447265625
                ),
                SensorKitPPGRecording.AccelerometerSample(
                    nanosecondsSinceStart: 1344525599925125,
                    samplingFrequency: 64.0,
                    x: -0.4883270263671875,
                    y: 0.72552490234375,
                    z: 0.480499267578125
                ),
                SensorKitPPGRecording.AccelerometerSample(
                    nanosecondsSinceStart: 1344525615550125,
                    samplingFrequency: 64.0,
                    x: -0.488189697265625,
                    y: 0.727264404296875,
                    z: 0.48175048828125
                ),
                SensorKitPPGRecording.AccelerometerSample(
                    nanosecondsSinceStart: 1344525631175125,
                    samplingFrequency: 64.0,
                    x: -0.488525390625,
                    y: 0.7302703857421875,
                    z: 0.4838104248046875
                ),
                SensorKitPPGRecording.AccelerometerSample(
                    nanosecondsSinceStart: 1344525646800125,
                    samplingFrequency: 64.0,
                    x: -0.4892578125,
                    y: 0.7341461181640625,
                    z: 0.486358642578125
                ),
                SensorKitPPGRecording.AccelerometerSample(
                    nanosecondsSinceStart: 1344525662425125,
                    samplingFrequency: 64.0,
                    x: -0.48651123046875,
                    y: 0.730712890625,
                    z: 0.4849090576171875
                ),
                SensorKitPPGRecording.AccelerometerSample(
                    nanosecondsSinceStart: 1344525678050125,
                    samplingFrequency: 64.0,
                    x: -0.48016357421875,
                    y: 0.72637939453125,
                    z: 0.4789581298828125
                ),
                SensorKitPPGRecording.AccelerometerSample(
                    nanosecondsSinceStart: 1344525693675125,
                    samplingFrequency: 64.0,
                    x: -0.483917236328125,
                    y: 0.725250244140625,
                    z: 0.477752685546875
                )
            ]
        ),
        SensorKitPPGRecording.Record(
            startDate: Date(timeIntervalSince1970: 1767294887.6906688),
            nanosecondsSinceStart: 1346107022318958,
            temperature: 33.3125,
            usage: ["ForegroundHeartRate", "BackgroundSystem"],
            opticalSamples: [
                SensorKitPPGRecording.OpticalSample(
                    emitter: 10,
                    activePhotodiodeIndexes: [1, 2],
                    signalIdentifier: 0,
                    nominalWavelength: 525.0,
                    effectiveWavelength: 525.0,
                    samplingFrequency: 128.0,
                    nanosecondsSinceStart: 1346107022316208,
                    conditions: ["SignalSaturation"],
                    noiseTerms: .init(
                        whiteNoise: 3.311144964441258e-14,
                        pinkNoise: 7.17879477651201e-13,
                        backgroundNoise: -8.803055607131682e-06,
                        backgroundNoiseOffset: 2.0059102219961017e-13
                    ),
                    normalizedReflectance: 0.04843564331531525
                ),
                SensorKitPPGRecording.OpticalSample(
                    emitter: 12,
                    activePhotodiodeIndexes: [0, 3],
                    signalIdentifier: 0,
                    nominalWavelength: 525.0,
                    effectiveWavelength: 525.0,
                    samplingFrequency: 128.0,
                    nanosecondsSinceStart: 1346107022317125,
                    conditions: ["SignalSaturation"],
                    noiseTerms: .init(
                        whiteNoise: 3.3039550099717846e-14,
                        pinkNoise: 7.192040474453265e-13,
                        backgroundNoise: -7.045726761134574e-06,
                        backgroundNoiseOffset: 1.988823873384088e-13
                    ),
                    normalizedReflectance: 0.048480309545993805
                )
            ],
            accelerometerSamples: [
                SensorKitPPGRecording.AccelerometerSample(
                    nanosecondsSinceStart: 1346106912943958,
                    samplingFrequency: 64.0,
                    x: 0.277587890625,
                    y: 0.81646728515625,
                    z: -0.2883758544921875
                ),
                SensorKitPPGRecording.AccelerometerSample(
                    nanosecondsSinceStart: 1346106928568958,
                    samplingFrequency: 64.0,
                    x: 0.3888702392578125,
                    y: 1.105133056640625,
                    z: -0.3709716796875
                ),
                SensorKitPPGRecording.AccelerometerSample(
                    nanosecondsSinceStart: 1346106944193958,
                    samplingFrequency: 64.0,
                    x: 0.305145263671875,
                    y: 1.0943603515625,
                    z: -0.296966552734375
                ),
                SensorKitPPGRecording.AccelerometerSample(
                    nanosecondsSinceStart: 1346106959818958,
                    samplingFrequency: 64.0,
                    x: 0.1283111572265625,
                    y: 0.8650970458984375,
                    z: -0.155548095703125
                ),
                SensorKitPPGRecording.AccelerometerSample(
                    nanosecondsSinceStart: 1346106975443958,
                    samplingFrequency: 64.0,
                    x: -0.02215576171875,
                    y: 0.879364013671875,
                    z: -0.1072540283203125
                ),
                SensorKitPPGRecording.AccelerometerSample(
                    nanosecondsSinceStart: 1346106991068958,
                    samplingFrequency: 64.0,
                    x: -0.089019775390625,
                    y: 1.0381622314453125,
                    z: -0.2420654296875
                ),
                SensorKitPPGRecording.AccelerometerSample(
                    nanosecondsSinceStart: 1346107006693958,
                    samplingFrequency: 64.0,
                    x: -0.06451416015625,
                    y: 1.0237274169921875,
                    z: -0.3580322265625
                ),
                SensorKitPPGRecording.AccelerometerSample(
                    nanosecondsSinceStart: 1346107022318958,
                    samplingFrequency: 64.0,
                    x: 0.0022430419921875,
                    y: 0.9289703369140625,
                    z: -0.3621673583984375
                )
            ]
        )
    ]

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

    @Test("Bytes My Heart Counts' own encoder wrote decode to the samples it encoded")
    func myHeartCountsEncoderBytesDecode() throws {
        let data = try #require(Self.myHeartCountsEncoded)
        #expect(try SensorKitPPGRecording(legacyMyHeartCountsData: data).records == Self.myHeartCountsSamples)
    }
}
