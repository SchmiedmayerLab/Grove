//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation

// The input schema of `content-corpus.jsonl`: every type here is Codable as the corpus prints it, and every field
// is documented as the data it states. Inputs compare by their printed text (`ContentCorpusStore.inputText`), so
// no type is Hashable, which a NaN reading would make irreflexive.


/// One metadata value as HealthKit stores it: a string, an integer or floating-point number, or a Boolean.
///
/// Encoded as a one-member object naming its kind, so `1`, `1.0` and `true` stay three different inputs.
enum ContentCorpusMetadataValue: Codable, Sendable {
    /// A string, as `NSString` stores it.
    case string(String)
    /// An integer, as `NSNumber` stores it.
    case integer(Int)
    /// A floating-point number, as `NSNumber` stores it.
    case double(Double)
    /// A Boolean, as `NSNumber` stores it.
    case boolean(Bool)

    /// The member naming the value's kind.
    private enum CodingKeys: String, CodingKey {
        case string
        case integer
        case double
        case boolean
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "one kind per metadata value"))
        }
        self = switch key {
        case .string: .string(try container.decode(String.self, forKey: key))
        case .integer: .integer(try container.decode(Int.self, forKey: key))
        case .double: .double(try container.decode(Double.self, forKey: key))
        case .boolean: .boolean(try container.decode(Bool.self, forKey: key))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let text): try container.encode(text, forKey: .string)
        case .integer(let number): try container.encode(number, forKey: .integer)
        case .double(let number): try container.encode(number, forKey: .double)
        case .boolean(let flag): try container.encode(flag, forKey: .boolean)
        }
    }
}


/// A JSON document stated inside an input, such as the Observation a reverse projection reads: nested as JSON, not
/// escaped into a string, with every number kept as the exact decimal its lexeme states.
indirect enum ContentCorpusJSON: Codable, Sendable {
    /// An object, its members by key.
    case object([String: ContentCorpusJSON])
    /// An array, in order.
    case array([ContentCorpusJSON])
    /// A string.
    case string(String)
    /// A number, as the exact decimal its lexeme states.
    case number(Decimal)
    /// `true` or `false`.
    case boolean(Bool)
    /// `null`.
    case null

    /// The document Foundation's JSON serialization prints for `object`, read back exactly.
    init(serializing object: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        self = try JSONDecoder().decode(Self.self, from: data)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Each kind is tried in turn; a mismatch is the expected answer for every kind but one.
        if container.decodeNil() {
            self = .null
        } else if let flag = try? container.decode(Bool.self) {
            self = .boolean(flag)
        } else if let number = try? container.decode(Decimal.self) {
            self = .number(number)
        } else if let text = try? container.decode(String.self) {
            self = .string(text)
        } else if let elements = try? container.decode([Self].self) {
            self = .array(elements)
        } else {
            self = .object(try container.decode([String: Self].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let members): try container.encode(members)
        case .array(let elements): try container.encode(elements)
        case .string(let text): try container.encode(text)
        case .number(let number): try container.encode(number)
        case .boolean(let flag): try container.encode(flag)
        case .null: try container.encodeNil()
        }
    }

    /// The document decoded as `Value`, from the bytes JSON encoding prints for it.
    func decoded<Value: Decodable>(as type: Value.Type) throws -> Value {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }
}


/// One member of a correlation: its quantity type, value in `unit`, and the metadata it states itself.
struct ContentCorpusMember: Codable, Sendable {
    /// The member's quantity type identifier.
    var type: String
    /// The member's reading, in `unit`.
    var value: Double
    /// The unit the reading is stated in, as `HKUnit(from:)` parses it.
    var unit = "mmHg"
    /// The metadata the member states itself, apart from the correlation's.
    var metadata: [String: ContentCorpusMetadataValue] = [:]
}


/// One workout statistic, each reading in `unit`; an absent reading is one HealthKit did not report.
struct ContentCorpusStatistic: Codable, Sendable {
    /// The statistic's quantity type identifier.
    var type: String
    /// The unit every reading is stated in, as `HKUnit(from:)` parses it.
    var unit: String
    /// The cumulative reading.
    var sum: Double?
    /// The average reading.
    var average: Double?
    /// The smallest reading.
    var minimum: Double?
    /// The largest reading.
    var maximum: Double?
}


/// An ECG's reading, voltages and correlated symptoms, as raw as HealthKit reports them.
struct ContentCorpusElectrocardiogram: Codable, Sendable {
    /// One voltage measurement; a nil voltage states no lead at all.
    struct Voltage: Codable, Sendable {
        /// Seconds since the ECG's start.
        var offset: Double
        /// The lead's voltage in millivolts.
        var millivolts: Double?
    }

    /// One correlated symptom sample: a category type, its raw value, and the last byte of its UUID. It converts
    /// under the event after the ECG's and those of the symptoms before it.
    struct Symptom: Codable, Sendable {
        /// The symptom's category type identifier.
        var type: String
        /// The symptom's raw category value.
        var value: Int
        /// The last byte of the symptom's UUID (`GoldenFixtures.uuid(_:)`).
        var ordinal: UInt8
    }

    /// The raw `HKElectrocardiogram.Classification`.
    var classification: Int
    /// The raw `HKElectrocardiogram.SymptomsStatus`.
    var symptomsStatus: Int
    /// How many voltages HealthKit reports the recording to have.
    var reportedCount: Int
    /// The average heart rate in beats per minute.
    var averageHeartRate: Double?
    /// The sampling frequency in hertz.
    var samplingFrequency: Double?
    /// The lead's voltages in the order HealthKit delivers them.
    var voltages: [Voltage]
    /// The symptom samples correlated with the ECG, in the record's order.
    var symptoms: [Symptom] = []
}


/// One heartbeat of a series: seconds since the series start, and whether a gap preceded it.
struct ContentCorpusBeat: Codable, Sendable {
    /// Seconds since the series start.
    var offset: Double
    /// Whether the recording paused before this beat.
    var gap: Bool
}


/// One route fix, `offset` seconds after the route starts; CoreLocation reports an unavailable reading as negative.
struct ContentCorpusLocation: Codable, Sendable {
    /// Seconds since the route's start.
    var offset: Double
    /// Degrees north.
    var latitude: Double
    /// Degrees east.
    var longitude: Double
    /// Meters above sea level.
    var altitude: Double
    /// Meters; negative when unavailable.
    var horizontalAccuracy: Double
    /// Meters; negative when unavailable.
    var verticalAccuracy: Double
    /// Degrees from true north; negative when unavailable.
    var course: Double
    /// Degrees; negative when unavailable.
    var courseAccuracy: Double
    /// Meters per second; negative when unavailable.
    var speed: Double
    /// Meters per second; negative when unavailable.
    var speedAccuracy: Double
}


/// The payload of one source record, by the HealthKit class that carries it.
enum ContentCorpusRecord: Codable, Sendable {
    /// A quantity sample of `value` in `unit` (as `HKUnit(from:)` parses it).
    case quantity(type: String, value: Double, unit: String)
    /// A category sample with any raw value, admitted by HealthKit or not.
    case category(type: String, value: Int)
    /// A correlation of exactly `members`.
    case correlation(type: String, members: [ContentCorpusMember])
    /// A workout of any raw activity type, `duration` seconds long, with `statistics` in its primary activity.
    case workout(activity: UInt, duration: Double, statistics: [ContentCorpusStatistic])
    /// A reflection of any raw kind, labels and associations.
    case stateOfMind(kind: Int, valence: Double, labels: [Int], associations: [Int])
    /// A GAD-7 or PHQ-9 assessment stating any score.
    case assessment(type: String, score: Int)
    /// An ECG with its companion data, converted through the record entry point.
    case electrocardiogram(reading: ContentCorpusElectrocardiogram)
    /// A heartbeat series with its beats.
    case heartbeatSeries(beats: [ContentCorpusBeat])
    /// A route with its fixes; `disclosed` is the route-disclosure policy.
    case workoutRoute(locations: [ContentCorpusLocation], disclosed: Bool)
    /// A CDA document sample; a nil document is one fetched without its document data.
    case cdaDocument(title: String, document: String?)
    /// A clinical record; a nil resource is one HealthKit returned without its FHIR resource.
    case clinicalRecord(type: String, fhirVersion: String, resource: String?)
    /// A bare instance of `sampleClass` with no payload, passed to the plain sample entry point.
    case bare(type: String, sampleClass: String)
}


/// One source record and the facts its sample carries besides its payload.
struct ContentCorpusSource: Codable, Sendable {
    /// The `HKDevice` the sample names.
    enum Device: String, Codable, Sendable {
        /// A watch with a per-unit token, so the graph carries a recording Device.
        case watch
        /// The same watch without one, whose omission is reported.
        case watchWithoutUnitToken
    }

    /// The `HKSourceRevision` the sample is attributed to.
    enum Writer: String, Codable, Sendable {
        /// No source at all, so the graph carries no writer.
        case unattributed
        /// A third-party application on its own phone.
        case foreign
    }

    /// The event context the record converts under.
    enum Context: String, Codable, Sendable {
        /// The suite's default context.
        case plain
        /// A gateway converter with one bundled study, so every output link a slot admits applies.
        case linked
    }

    /// The record's payload.
    var record: ContentCorpusRecord
    /// The sample's start, in seconds since 1970.
    var start: Double
    /// The sample's end, in seconds since 1970.
    var end: Double
    /// The sample's metadata.
    var metadata: [String: ContentCorpusMetadataValue]
    /// The device the sample names, if any.
    var device: Device?
    /// The writer the sample is attributed to.
    var writer: Writer
    /// The event context the record converts under.
    var context: Context
}


/// A disclosure policy a retraction is named under.
enum ContentCorpusDisclosure: String, Codable, Sendable {
    /// The store's UUID travels as each target's native record identifier, under `GoldenFixtures.nativeIdentifierSystem`.
    case nativeIdentifier
}


/// One part of the public catalog surface.
enum ContentCorpusProjection: Codable, Sendable {
    /// A source type's inventory row, outputs and field dispositions.
    case entry(type: String)
    /// Every published unit binding, in order.
    case unitBindings
    /// Both unit lookups for each spelling.
    case unitSpellings(spellings: [String])
}


/// One corpus line's key and input.
struct ContentCorpusVector: Sendable {
    /// The line's stable key.
    let id: String
    /// What the line feeds the converter.
    let input: ContentCorpusInput
}


/// What one content-corpus vector feeds the converter, stated as data so the corpus rebuilds every record
/// from the checked-in file alone, through `StoredSampleFixtures`, whatever code produced the line.
enum ContentCorpusInput: Codable, Sendable {
    /// Convert one source record.
    case convert(source: ContentCorpusSource)
    /// Convert one source record, then project every Observation of its graphs, read from the wire bytes, back to
    /// the HealthKit sample it describes.
    case roundTrip(source: ContentCorpusSource)
    /// Name the outputs a deletion of a record of this type retracts, under the default policies or `disclosure`.
    case retract(type: String, disclosure: ContentCorpusDisclosure? = nil)
    /// Project one part of the public catalog.
    case catalog(projection: ContentCorpusProjection)
    /// Project one Observation back to the HealthKit sample it describes.
    case reverse(observation: ContentCorpusJSON)
}

#endif
