//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation


/// One metadata value as HealthKit stores it: a string, an integer or floating-point number, or a Boolean.
///
/// Encoded as a one-member object naming its kind, so `1`, `1.0` and `true` stay three different inputs.
enum ContentCorpusMetadataValue: Codable, Hashable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)

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


/// One member of a correlation: its quantity type, value in `unit`, and the metadata it states itself.
struct ContentCorpusMember: Codable, Hashable, Sendable {
    var type: String
    var value: Double
    var unit = "mmHg"
    var metadata: [String: ContentCorpusMetadataValue] = [:]
}


/// One workout statistic, each reading in `unit`; an absent reading is one HealthKit did not report.
struct ContentCorpusStatistic: Codable, Hashable, Sendable {
    var type: String
    var unit: String
    var sum: Double?
    var average: Double?
    var minimum: Double?
    var maximum: Double?
}


/// An ECG's reading, voltages and correlated symptoms, as raw as HealthKit reports them.
struct ContentCorpusElectrocardiogram: Codable, Hashable, Sendable {
    /// One voltage measurement; a nil voltage states no lead at all.
    struct Voltage: Codable, Hashable, Sendable {
        var offset: Double
        var millivolts: Double?
    }

    /// One correlated symptom sample, with its own UUID ordinal and the event context it converts under.
    struct Symptom: Codable, Hashable, Sendable {
        var type: String
        var value: Int
        var ordinal: UInt8
    }

    var classification: Int
    var symptomsStatus: Int
    var reportedCount: Int
    var averageHeartRate: Double?
    var samplingFrequency: Double?
    var voltages: [Voltage]
    var symptoms: [Symptom] = []
    /// How many symptom contexts the caller supplies, when that is not one per symptom.
    var symptomContexts: Int?
}


/// One heartbeat of a series: seconds since the series start, and whether a gap preceded it.
struct ContentCorpusBeat: Codable, Hashable, Sendable {
    var offset: Double
    var gap: Bool
}


/// One route fix, `offset` seconds after the route starts; CoreLocation reports an unavailable reading as negative.
struct ContentCorpusLocation: Codable, Hashable, Sendable {
    var offset: Double
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var horizontalAccuracy: Double
    var verticalAccuracy: Double
    var course: Double
    var courseAccuracy: Double
    var speed: Double
    var speedAccuracy: Double
}


/// The payload of one source record, by the HealthKit class that carries it.
enum ContentCorpusRecord: Codable, Hashable, Sendable {
    case quantity(type: String, value: Double, unit: String)
    /// A category sample with any raw value, admitted by HealthKit or not.
    case category(type: String, value: Int)
    case correlation(type: String, members: [ContentCorpusMember])
    case workout(activity: UInt, duration: Double, statistics: [ContentCorpusStatistic])
    case stateOfMind(kind: Int, valence: Double, labels: [Int], associations: [Int])
    case assessment(type: String, score: Int)
    /// An ECG with its companion data, converted through the record entry point.
    case electrocardiogram(reading: ContentCorpusElectrocardiogram)
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
struct ContentCorpusSource: Codable, Hashable, Sendable {
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

    var record: ContentCorpusRecord
    /// The sample's start, in seconds since 1970.
    var start: Double
    /// The sample's end, in seconds since 1970.
    var end: Double
    var metadata: [String: ContentCorpusMetadataValue]
    var device: Device?
    var writer: Writer
    var context: Context
}


/// One part of the public catalog surface.
enum ContentCorpusProjection: Codable, Hashable, Sendable {
    /// A source type's inventory row, outputs and field dispositions.
    case entry(type: String)
    /// Every published unit binding, in order.
    case unitBindings
    /// Both unit lookups for each spelling.
    case unitSpellings(spellings: [String])
    /// The sample an Observation, given as its JSON, projects back to.
    case reverse(observation: String)
}


/// One corpus line's key and input.
struct ContentCorpusVector: Hashable, Sendable {
    let id: String
    let input: ContentCorpusInput
}


/// What one content-corpus vector feeds the converter, stated as data so the corpus rebuilds every record
/// from the checked-in file alone, through `StoredSampleFixtures`, whatever code produced the line.
enum ContentCorpusInput: Codable, Hashable, Sendable {
    /// Convert one source record.
    case convert(source: ContentCorpusSource)
    /// Name the outputs a deletion of a record of this type retracts.
    case retract(type: String)
    /// Project one part of the public catalog.
    case catalog(projection: ContentCorpusProjection)
}

#endif
