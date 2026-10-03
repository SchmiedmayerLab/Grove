//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import HealthKit
import ObjectiveC


/// TEST-ONLY. Builds HealthKit samples the way the store hands them back: with a chosen UUID, an
/// attributable `HKSourceRevision`, and (for the classes HealthKit offers no synthetic initializer for, or
/// for facts it refuses at creation) chosen dates, device, metadata and payload.
///
/// HealthKit's public factories mint a fresh UUID and attribute every sample to the running
/// process, so no test can otherwise pin a graph whose identities derive from the UUID, or one that
/// carries writer and writer-host Device entries. The helper writes HealthKit's private ivars
/// through key-value coding (`_UUID`, `_sourceRevision`, ...); such a sample behaves like a fetched
/// one, including through an `NSKeyedArchiver` round trip.
///
/// Only this type touches private storage, and only the ivars its key table declares for each class:
/// ``instance(of:stating:)``, ``restate(_:with:)`` and ``read(_:of:)`` refuse any other key, and
/// `StoredSampleFixturesTests` fails, and never skips, the moment HealthKit stops declaring one, so a silent
/// regression into process-attributed samples cannot hide behind green goldens. The per-class builders the
/// content corpus uses live in `StoredSampleFixtures+Corpus.swift`.
///
/// Nothing here may be used outside the test target.
enum StoredSampleFixtures {
    /// The writer a stored sample is attributed to, as `HKSourceRevision` states it.
    struct Writer: Sendable {
        /// A source without a name or bundle identifier, which the converter treats as no writer at all; what a
        /// sample built in-process reports when nothing attributes it.
        static let unattributed = Writer(name: "", bundleIdentifier: "", version: nil, productType: nil)

        /// The source's display name.
        var name: String
        /// The source's bundle identifier.
        var bundleIdentifier: String
        /// The revision's version, as the writing application stated it.
        var version: String?
        /// The model of the device the writer ran on.
        var productType: String?
        /// The operating system the writer ran on.
        var operatingSystemVersion = OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0)
    }

    /// Every fact a stored sample states besides its payload: its UUID, interval, device, metadata and writer.
    ///
    /// ``seriesSample(_:sampleType:facts:)`` builds a bare sample carrying exactly these facts, and
    /// ``restated(_:facts:)`` states them on a built sample in place of what its initializer stated.
    struct SampleFacts: Sendable {
        /// The UUID the store gave the sample.
        var uuid: UUID
        /// When the sample starts.
        var start: Date
        /// When the sample ends; any instant, also one before `start`.
        var end: Date
        /// The device the sample names.
        var device: HKDevice?
        /// The metadata the sample carries, nil for none.
        var metadata: [String: any Sendable]?  // swiftlint:disable:this discouraged_optional_collection
        /// The source revision the sample is attributed to.
        var writer: Writer
    }

    /// HealthKit no longer keeps a fact where the fixtures put it.
    enum FixtureError: Error, CustomStringConvertible {
        /// HealthKit refused to allocate a bare instance of the class.
        case classNotConstructible(String)
        /// The class no longer declares, or reads back, the private key.
        case keyNotHonored(key: String, class: String)
        /// A fixture asked for a key the key table does not declare for the class.
        case keyNotDeclared(key: String, class: String)
        /// The unit does not measure the quantity type, so HealthKit would raise instead of converting.
        case incompatibleUnit(unit: String, type: String)

        var description: String {
            switch self {
            case .classNotConstructible(let name):
                "HealthKit refused to allocate a bare \(name); the stored-sample fixtures need a new strategy"
            case let .keyNotHonored(key, name):
                "\(name) no longer reads back the value written to '\(key)'; the stored-sample fixtures need a new strategy"
            case let .keyNotDeclared(key, name):
                "the stored-sample fixtures declare no private key '\(key)' for \(name); add it to the key table first"
            case let .incompatibleUnit(unit, type):
                "\(unit) does not measure \(type)"
            }
        }
    }

    /// Every private ivar the fixtures write or read, by the HealthKit class that declares it (without the leading
    /// underscore); a key is honored on that class and its subclasses, and nowhere else.
    private static let privateKeys: [(className: String, keys: [String])] = {
        var table: [(className: String, keys: [String])] = [
            ("HKObject", ["UUID", "sourceRevision", "device", "metadata"]),
            ("HKSample", ["sampleType", "startTimestamp", "endTimestamp"]),
            ("HKSource", ["name", "bundleIdentifier"]),
            ("HKQuantitySample", ["quantity", "count"]),
            ("HKCategorySample", ["value"]),
            ("HKCorrelation", ["objects"]),
            ("HKWorkout", ["workoutActivityType", "duration", "primaryActivity"]),
            ("HKWorkoutActivity", ["statisticsPerType"]),
            ("HKStatistics", ["dataType", "sumQuantity", "averageQuantity", "minimumQuantity", "maximumQuantity"]),
            ("HKStateOfMind", ["kind", "valence", "labels", "associations"]),
            ("HKScoredAssessment", ["score"]),
            ("HKElectrocardiogramVoltageMeasurement", ["timeSinceSampleStart", "leadIVoltage"])
        ]
        #if !os(watchOS)
        table += [
            ("HKCDADocumentSample", ["document"]),
            ("HKCDADocument", ["internalDocumentData", "title"]),
            ("HKClinicalRecord", ["FHIRResource"]),
            ("HKFHIRResource", ["data", "FHIRVersion"])
        ]
        #endif
        return table
    }()

    /// An `HKSource` naming the writing application; HealthKit itself only ever vends one for the running process.
    static func source(name: String, bundleIdentifier: String) throws -> HKSource {
        try instance(of: HKSource.self, stating: ["name": name, "bundleIdentifier": bundleIdentifier])
    }

    /// The source revision a stored sample attributed to `writer` carries.
    static func sourceRevision(_ writer: Writer) throws -> HKSourceRevision {
        HKSourceRevision(
            source: try source(name: writer.name, bundleIdentifier: writer.bundleIdentifier),
            version: writer.version,
            productType: writer.productType,
            operatingSystemVersion: writer.operatingSystemVersion
        )
    }

    /// `sample` with the UUID the store would have given it and, when `writer` is given, its source revision;
    /// every other fact stays as built.
    ///
    /// Without a writer the sample keeps the revision its factory gave it, which names no source at all. That is
    /// the only shape `HKCorrelation`'s initializer admits for its objects: one that already states a writer is
    /// validated against the process's default source, which a test process does not have.
    static func stored<Sample: HKSample>(_ sample: Sample, uuid: UUID, writer: Writer? = nil) throws -> Sample {
        try write(uuid, to: "UUID", of: sample)
        if let writer {
            try write(try sourceRevision(writer), to: "sourceRevision", of: sample)
        }
        try verify(sample, uuid: uuid, writer: writer)
        return sample
    }

    /// `sample` carrying exactly `metadata`, written past HealthKit's initializer, which raises an Objective-C exception
    /// for a value it refuses (a half sync pair, a negative or textual sync version) instead of returning one.
    static func withMetadata<Sample: HKSample>(_ sample: Sample, _ metadata: [String: Any]) throws -> Sample {
        try restate(sample, with: ["metadata": metadata as NSDictionary])
        guard (sample.metadata ?? [:]).keys.sorted() == metadata.keys.sorted() else {
            throw FixtureError.keyNotHonored(key: "metadata", class: String(describing: type(of: sample)))
        }
        return sample
    }

    /// A bare instance of a sample class without a public initializer, carrying exactly `facts`.
    static func seriesSample<Sample: HKSample>(_ type: Sample.Type, sampleType: HKSampleType, facts: SampleFacts) throws -> Sample {
        let sample = try restated(try instance(of: type, stating: ["sampleType": sampleType]), facts: facts)
        guard sample.sampleType == sampleType else {
            throw FixtureError.keyNotHonored(key: "sampleType", class: String(describing: type))
        }
        return sample
    }

    /// `sample` carrying exactly `facts` in place of the ones its initializer stated.
    ///
    /// HealthKit validates a sample only when it creates one, so a fact it refuses there (a reversed interval,
    /// a metadata value of the wrong type, an instant after 4000) can be stated only afterwards, as here.
    static func restated<Sample: HKSample>(_ sample: Sample, facts: SampleFacts) throws -> Sample {
        try write(NSNumber(value: facts.start.timeIntervalSinceReferenceDate), to: "startTimestamp", of: sample)
        try write(NSNumber(value: facts.end.timeIntervalSinceReferenceDate), to: "endTimestamp", of: sample)
        try write(facts.device, to: "device", of: sample)
        try write(facts.metadata, to: "metadata", of: sample)
        let stored = try stored(sample, uuid: facts.uuid, writer: facts.writer)
        let name = String(describing: type(of: sample))
        guard stored.startDate == facts.start, stored.endDate == facts.end else {
            throw FixtureError.keyNotHonored(key: "startTimestamp/endTimestamp", class: name)
        }
        guard stored.device == facts.device, (stored.metadata ?? [:]).keys.sorted() == (facts.metadata ?? [:]).keys.sorted() else {
            throw FixtureError.keyNotHonored(key: "device/metadata", class: name)
        }
        return stored
    }

    /// Whether every class in the key table still exists and still declares every key, checked before a single
    /// value is written.
    static func privateStorageIsPresent() -> Bool {
        privateKeys.allSatisfy { className, keys in
            guard let declaring = NSClassFromString(className) else {
                return false
            }
            return keys.allSatisfy { class_getInstanceVariable(declaring, "_\($0)") != nil }
        }
    }

    /// A bare instance of `type`, none of whose initializers ran, carrying `facts` in its private storage.
    static func instance<Object: NSObject>(of type: Object.Type, stating facts: KeyValuePairs<String, Any?>) throws -> Object {
        guard let object = class_createInstance(type, 0) as? NSObject else {
            throw FixtureError.classNotConstructible(String(describing: type))
        }
        try restate(object, with: facts)
        return unsafeDowncast(object, to: type)
    }

    /// States `facts` in `object`'s private storage, each under a key the key table declares for its class.
    static func restate(_ object: NSObject, with facts: KeyValuePairs<String, Any?>) throws {
        for (key, value) in facts {
            try write(value, to: key, of: object)
        }
    }

    /// One private ivar's value, read through key-value coding only while the class still declares the key, so a
    /// HealthKit that dropped it fails with ``FixtureError/keyNotHonored(key:class:)`` instead of raising.
    static func read(_ key: String, of object: NSObject) throws -> Any? {
        try requireDeclared(key, on: object)
        return object.value(forKey: key)
    }

    /// Writes one private ivar through key-value coding, failing when the key table or the class lacks it.
    private static func write(_ value: Any?, to key: String, of object: NSObject) throws {
        try requireDeclared(key, on: object)
        object.setValue(value, forKey: key)
    }

    /// Fails unless the key table declares `key` for a class `object` is a kind of, and the class still has it.
    private static func requireDeclared(_ key: String, on object: NSObject) throws {
        let name = String(describing: type(of: object))
        let declared = privateKeys.contains { className, keys in
            keys.contains(key) && NSClassFromString(className).map { object.isKind(of: $0) } == true
        }
        guard declared else {
            throw FixtureError.keyNotDeclared(key: key, class: name)
        }
        guard class_getInstanceVariable(type(of: object), "_\(key)") != nil else {
            throw FixtureError.keyNotHonored(key: key, class: name)
        }
    }

    /// Fails unless `sample` reports the UUID and, when given, the writer that were written.
    private static func verify(_ sample: HKSample, uuid: UUID, writer: Writer?) throws {
        let name = String(describing: type(of: sample))
        guard sample.uuid == uuid else {
            throw FixtureError.keyNotHonored(key: "UUID", class: name)
        }
        guard let writer else {
            return
        }
        let revision = sample.sourceRevision
        guard revision.source.name == writer.name,
              revision.source.bundleIdentifier == writer.bundleIdentifier,
              revision.version == writer.version,
              revision.productType == writer.productType,
              revision.operatingSystemVersion.majorVersion == writer.operatingSystemVersion.majorVersion,
              revision.operatingSystemVersion.minorVersion == writer.operatingSystemVersion.minorVersion,
              revision.operatingSystemVersion.patchVersion == writer.operatingSystemVersion.patchVersion else {
            throw FixtureError.keyNotHonored(key: "sourceRevision", class: name)
        }
    }
}

#endif
